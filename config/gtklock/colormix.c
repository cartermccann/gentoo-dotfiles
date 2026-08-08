// atlas-colormix — a gtklock module reproducing Ly's `colormix` animation live.
//
// Ly draws its background by evaluating a domain-warped plasma once per terminal
// CELL and painting one of 12 palette entries there. This module does exactly the
// same thing on a cairo surface sized in cells, then blits it up with a NEAREST
// filter. The cell quantisation IS the look — render it per-pixel or scale it
// with a smoothing filter and it stops resembling Ly immediately.
//
// Ported from ly/src/animations/ColorMix.zig (see draw(), lines 87-119). The
// arithmetic below is a transcription; if you change it, change it there first
// and re-derive, because the constants are not arbitrary.
//
// BUILD: run build.sh in this directory (a single gcc -shared line).
//
// LOAD: modules=/home/cjm/.config/gtklock/colormix.so   (in config.ini)
//
// SAFETY NOTES — this code runs inside a lock screen, where a crash means the
// compositor stays locked with no client to authenticate against:
//   * nothing is allocated in the draw path except the cell surface, and that
//     only when the window size actually changes
//   * the palette index is clamped, and non-finite intermediates bail to 0
//   * if the surface cannot be created we return FALSE and simply do not paint;
//     the window's CSS background (colormix.png) shows through as a fallback

#include <gtk/gtk.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

// Checked by gtklock's module_load(). A MAJOR mismatch is fatal — it calls
// report_error_and_exit() and gtklock never starts. Matches gtklock 4.0.0.
guint module_major_version = 4;
guint module_minor_version = 0;

// ── Ly parity ────────────────────────────────────────────────────────────────
// Colours from /etc/ly/config.ini (colormix_col1/2/3). col3 there is
// 0x20000000: termbox's TB_HI_BLACK attribute over #000000, i.e. true black.
#define COL1_R 0x3B
#define COL1_G 0x6B
#define COL1_B 0xFF
#define COL2_R 0x10
#define COL2_G 0x2A
#define COL2_B 0x66
#define COL3_R 0x00
#define COL3_G 0x00
#define COL3_B 0x00

#define TIME_SCALE 0.01f       // ColorMix.zig:17
#define PALETTE_LEN 12         // ColorMix.zig:18

// Ly's animation_frame_delay from config.ini. Deriving `frames` from wall-clock
// against this constant (rather than counting our own redraws) keeps the motion
// at exactly Ly's speed no matter what rate we choose to render at.
#define LY_FRAME_DELAY_MS 24.0

// The console font cell — this sets the apparent "pixel" size, and it MUST match
// whatever /etc/conf.d/consolefont sets or the lock screen's blocks come out a
// different size from the greeter's and the two stop looking related.
//
//   ter-u24b  12x24      ter-u28b  14x28      ter-u32b  16x32   <- current
//
// NOT the 8x16 kernel default: atlas overrides the console font, so assuming the
// default is wrong here. Check /etc/conf.d/consolefont before changing these.
// Override at runtime with ATLAS_COLORMIX_CELL_W / _H.
#define DEFAULT_CELL_W 16
#define DEFAULT_CELL_H 32

static int cell_w = DEFAULT_CELL_W;
static int cell_h = DEFAULT_CELL_H;

// We render far below the frame clock. The pattern needs ~2.5 minutes for a full
// 2*pi cycle, so a low rate is visually indistinguishable from 60fps.
//
// This is not a micro-optimisation, and the reason is not the one you would
// guess. Measured on this machine (nested 1308x1494 window):
//
//     fps    2      5     10     20
//     CPU  3.9%   6.4%  10.1%  16.2%
//
// i.e. roughly 2.4% baseline + 0.7% per fps. Cost tracks the FRAME RATE, not the
// cell count — going from a 300x100 grid to 150x50 (a quarter of the cells, and
// therefore a quarter of the trig) moved it only 11.4% -> 10.1%. What dominates
// is the per-frame full-window blit and compositing, so fps is the only lever
// that matters. Scale up ~1.9x for a real 2400x1600 screen.
//
// 6fps is indistinguishable from 60 for a pattern that takes ~2.5 minutes per
// cycle. Raise it with ATLAS_COLORMIX_FPS if you disagree.
#define DEFAULT_RENDER_FPS 6

// Ly's animation_timeout_sec: stop animating after N seconds and hold the last
// frame. /etc/ly/config.ini sets 0 (run forever) because a greeter is only on
// screen briefly — a lock screen is not, so ATLAS_COLORMIX_TIMEOUT_SEC exists to
// cap the burn. 0 keeps Ly's behaviour and is the default.
#define DEFAULT_TIMEOUT_SEC 0

static gint64 render_interval_us = G_USEC_PER_SEC / DEFAULT_RENDER_FPS;
static gint64 anim_timeout_us = 0;   // 0 = never stop

// Redraw rate once frozen — still enough to keep the block clock ticking.
#define FROZEN_INTERVAL_US G_USEC_PER_SEC

// Refuse absurd grids rather than allocate unbounded memory on a bad size.
#define MAX_CELLS (4096 * 4096)

// ── Ly's big clock ───────────────────────────────────────────────────────────
// From ly-ui/src/components/BigLabel.zig: each character is a fixed 5x5 grid of
// cells (CHAR_WIDTH = CHAR_HEIGHT = 5), advanced by CHAR_WIDTH+1 per glyph
// (BigLabel.zig:163). Set cells use U+2593 and unset cells use codepoint 0,
// which Cell.put() skips outright (Cell.zig:18) -- so the negative space inside
// a digit is TRANSPARENT and the plasma shows through it. That is why the clock
// reads as cut out of the animation rather than sitting on a panel.
//
// Bitmaps transcribed from bigLabelLocales/en.zig. One byte per row, bit 4 is
// the leftmost column.
#define GLYPH_W 5
#define GLYPH_H 5
#define GLYPH_ADVANCE 6

#define GI_COLON 10
#define GI_BLANK 11

static const guint8 big_glyphs[12][GLYPH_H] = {
	{ 0x1F, 0x1B, 0x1B, 0x1B, 0x1F },   // 0
	{ 0x03, 0x03, 0x03, 0x03, 0x03 },   // 1
	{ 0x1F, 0x03, 0x1F, 0x18, 0x1F },   // 2
	{ 0x1F, 0x03, 0x1F, 0x03, 0x1F },   // 3
	{ 0x1B, 0x1B, 0x1F, 0x03, 0x03 },   // 4
	{ 0x1F, 0x18, 0x1F, 0x03, 0x1F },   // 5
	{ 0x1F, 0x18, 0x1F, 0x1B, 0x1F },   // 6
	{ 0x1F, 0x03, 0x03, 0x03, 0x03 },   // 7
	{ 0x1F, 0x1B, 0x1F, 0x1B, 0x1F },   // 8
	{ 0x1F, 0x1B, 0x1F, 0x03, 0x1F },   // 9
	{ 0x00, 0x04, 0x00, 0x04, 0x00 },   // :   (S in en.zig)
	{ 0x00, 0x00, 0x00, 0x00, 0x00 },   // blank (E in en.zig)
};

// MUST match time-format in config.ini -- the module formats its own clock
// rather than reading gtklock's, to avoid vendoring struct GtkLock as well.
#define CLOCK_FORMAT "%H:%M"

// U+2593 is the 75% shade, not a full block, so a lit cell is 75% foreground
// over the background rather than solid white. Reproducing that is the
// difference between Ly's slightly-soft clock and a hard white one.
#define SHADE_2593 0.75f
static guint32 clock_color;

// ── Vendored from gtklock 4.0.0 include/window.h ─────────────────────────────
// The module receives a `struct Window *` and must know its layout to reach the
// overlay. Pinned to 4.0.0; the version check above is what makes that safe.
struct Window {
	GdkMonitor *monitor;
	GtkWidget *window;
	GtkWidget *overlay;
	GtkWidget *window_box;
	GtkWidget *body_revealer;
	GtkWidget *body_grid;
	GtkWidget *input_label;
	GtkWidget *input_field;
	GtkWidget *message_revealer;
	GtkWidget *message_scrolled_window;
	GtkWidget *message_box;
	GtkWidget *unlock_button;
	GtkWidget *error_label;
	GtkWidget *warning_label;
	GtkWidget *info_box;
	GtkWidget *time_box;
	GtkWidget *clock_label;
	GtkWidget *date_label;
	void *module_data[];
};

struct GtkLock;

// ── Module-global animation state ────────────────────────────────────────────
// Shared across windows on purpose: with two monitors Ly is one continuous
// field, so per-window start times or seeds would visibly desynchronise them.
static gint64 anim_start_us = 0;
static float pattern_cos_mod = 0.0f;
static float pattern_sin_mod = 0.0f;
static guint32 palette[PALETTE_LEN];

// Per-window scratch, owned by the widget via g_object_set_data_full().
typedef struct {
	cairo_surface_t *surface;
	int cols;
	int rows;
	gint64 last_render_us;
	// Borrowed, not owned: gtklock owns this widget. Used only to read its
	// allocation so the block clock lands exactly where the (transparent) GTK
	// clock label reserves space, which keeps the two from fighting over layout.
	GtkWidget *clock_label;
} Plasma;

static void plasma_free(gpointer data) {
	Plasma *p = data;
	if(p == NULL) return;
	if(p->surface != NULL) cairo_surface_destroy(p->surface);
	g_free(p);
}

// Build the 12 flat colours: four block glyphs (U+2588/2593/2592/2591 =
// 100/75/50/25% foreground coverage) over three colour pairs. Each Ly cell is a
// glyph in fg on bg, so its average colour is just that blend.
static void build_palette(void) {
	static const float coverage[4] = { 1.00f, 0.75f, 0.50f, 0.25f };
	static const guint8 pairs[3][6] = {
		{ COL1_R, COL1_G, COL1_B, COL2_R, COL2_G, COL2_B },
		{ COL2_R, COL2_G, COL2_B, COL3_R, COL3_G, COL3_B },
		{ COL3_R, COL3_G, COL3_B, COL1_R, COL1_G, COL1_B },
	};
	int n = 0;
	for(int p = 0; p < 3; p++) {
		for(int c = 0; c < 4; c++) {
			float k = coverage[c];
			guint32 r = (guint32)(pairs[p][0] * k + pairs[p][3] * (1.0f - k) + 0.5f);
			guint32 g = (guint32)(pairs[p][1] * k + pairs[p][4] * (1.0f - k) + 0.5f);
			guint32 b = (guint32)(pairs[p][2] * k + pairs[p][5] * (1.0f - k) + 0.5f);
			palette[n++] = (r << 16) | (g << 8) | b;   // CAIRO_FORMAT_RGB24
		}
	}

	// Ly's clock cells are U+2593 in `fg` over `bg` -- 75% white, not solid.
	{
		const float k = SHADE_2593;
		guint32 r = (guint32)(0xFF * k + 0x17 * (1.0f - k) + 0.5f);
		guint32 g = (guint32)(0xFF * k + 0x1B * (1.0f - k) + 0.5f);
		guint32 b = (guint32)(0xFF * k + 0x23 * (1.0f - k) + 0.5f);
		clock_color = (r << 16) | (g << 8) | b;
	}
}

// Map an ASCII byte to a big_glyphs row. BigLabel.zig:220-236 folds everything
// unrecognised onto the blank glyph rather than erroring.
static inline int glyph_index(char c) {
	if(c >= '0' && c <= '9') return c - '0';
	if(c == ':') return GI_COLON;
	return GI_BLANK;
}

// One cell of ColorMix.zig:100-116.
static inline guint32 sample_cell(int x, int y, int cols, int rows, float t) {
	// uv.x is divided by (rows*2) but uv.y by rows — that asymmetry compensates
	// for the 1:2 aspect of a console cell. Do not "fix" it.
	float uvx = (x * 2.0f - cols) / (rows * 2.0f);
	float uvy = (y * 2.0f - rows) / (float)rows;

	// uv2 begins as a splat of (uv.x + uv.y) into BOTH components.
	float uv2x = uvx + uvy;
	float uv2y = uv2x;

	for(int i = 0; i < 3; i++) {
		float len = sqrtf(uvx * uvx + uvy * uvy);
		// uv2 updates from the PRE-update uv ...
		uv2x += uvx + len;
		uv2y += uvy + len;
		// ... then uv updates from the POST-update uv2. The order is load-bearing.
		float nx = uvx + 0.5f * cosf(pattern_cos_mod + uv2y * 0.2f + t * 0.1f);
		float ny = uvy + 0.5f * sinf(pattern_sin_mod + uv2x - t * 0.1f);
		uvx = nx;
		uvy = ny;
		// A scalar splat subtracted from both components, using the new uv.
		float s = cosf(uvx + uvy) - sinf(uvx * 0.7f - uvy);
		uvx -= s;
		uvy -= s;
	}

	float d = sqrtf(uvx * uvx + uvy * uvy) * 5.0f;
	if(!isfinite(d)) return palette[0];
	int idx = (int)floorf(d);
	if(idx < 0) idx = 0;
	return palette[idx % PALETTE_LEN];
}

static gboolean on_overlay_draw(GtkWidget *widget, cairo_t *cr, gpointer data) {
	Plasma *p = data;
	if(p == NULL) return FALSE;

	int w = gtk_widget_get_allocated_width(widget);
	int h = gtk_widget_get_allocated_height(widget);
	if(w <= 0 || h <= 0) return FALSE;

	int cols = w / cell_w;
	int rows = h / cell_h;
	if(cols < 1) cols = 1;
	if(rows < 1) rows = 1;
	if((gint64)cols * rows > MAX_CELLS) return FALSE;

	if(p->surface == NULL || p->cols != cols || p->rows != rows) {
		if(p->surface != NULL) cairo_surface_destroy(p->surface);
		p->surface = cairo_image_surface_create(CAIRO_FORMAT_RGB24, cols, rows);
		p->cols = cols;
		p->rows = rows;
		p->last_render_us = 0;   // force a repaint into the new surface
	}
	if(p->surface == NULL) return FALSE;
	if(cairo_surface_status(p->surface) != CAIRO_STATUS_SUCCESS) return FALSE;

	// Ly's `frames` counter, reconstructed from wall-clock so our render rate
	// does not change the animation speed.
	gint64 now_us = g_get_monotonic_time();
	double elapsed_ms = (now_us - anim_start_us) / 1000.0;
	float t = (float)((elapsed_ms / LY_FRAME_DELAY_MS) * TIME_SCALE);

	// Freeze once the timeout has passed, holding whatever is in the surface.
	gboolean frozen = anim_timeout_us > 0 && (now_us - anim_start_us) > anim_timeout_us;

	// Recompute at the render rate; between those, re-blit the cached cells.
	if(p->last_render_us == 0 || now_us - p->last_render_us >= render_interval_us) {
		p->last_render_us = now_us;
		cairo_surface_flush(p->surface);
		unsigned char *base = cairo_image_surface_get_data(p->surface);
		int stride = cairo_image_surface_get_stride(p->surface);
		if(base != NULL) {
			// Where the clock goes, in cells. Derived from the GTK clock label's
			// allocation so the blocks land exactly in the space that label
			// reserves -- the label is styled transparent in style.css, so it
			// contributes layout and nothing else, and the two cannot disagree.
			int cx = 0, cy = 0, cwid = 0;
			gboolean have_clock = FALSE;
			char stamp[16] = { 0 };

			if(p->clock_label != NULL && gtk_widget_get_realized(p->clock_label)) {
				time_t now = time(NULL);
				struct tm tmv;
				if(localtime_r(&now, &tmv) != NULL &&
				   strftime(stamp, sizeof stamp, CLOCK_FORMAT, &tmv) > 0) {
					int n = (int)strlen(stamp);
					cwid = (n - 1) * GLYPH_ADVANCE + GLYPH_W;
					GtkAllocation alloc;
					int lx = 0, ly = 0;
					gtk_widget_get_allocation(p->clock_label, &alloc);
					if(gtk_widget_translate_coordinates(p->clock_label, widget, 0, 0, &lx, &ly)) {
						// Centre horizontally on the whole screen (Ly does), but take
						// the vertical band from the label.
						cx = (cols - cwid) / 2;
						cy = (ly + (alloc.height - GLYPH_H * cell_h) / 2) / cell_h;
						if(cx >= 0 && cy >= 0 && cx + cwid <= cols && cy + GLYPH_H <= rows)
							have_clock = TRUE;
					}
				}
			}

			// When frozen we stop redrawing the plasma, but the clock still has to
			// tick -- so repaint just the band beneath it rather than the screen.
			int y_lo = 0, y_hi = rows;
			if(frozen) {
				if(!have_clock) goto blit;
				y_lo = cy;
				y_hi = cy + GLYPH_H;
			}
			for(int y = y_lo; y < y_hi; y++) {
				guint32 *row = (guint32 *)(base + (size_t)y * stride);
				for(int x = 0; x < cols; x++) row[x] = sample_cell(x, y, cols, rows, t);
			}

			if(have_clock) {
				for(int i = 0; stamp[i] != '\0'; i++) {
					const guint8 *bits = big_glyphs[glyph_index(stamp[i])];
					int gx = cx + i * GLYPH_ADVANCE;
					for(int yy = 0; yy < GLYPH_H; yy++) {
						guint32 *row = (guint32 *)(base + (size_t)(cy + yy) * stride);
						for(int xx = 0; xx < GLYPH_W; xx++) {
							// bit 4 is the leftmost column. Unset bits are left alone:
							// that is Cell.put()'s ch==0 early-return, i.e. the plasma
							// shows through the digit's negative space.
							if(bits[yy] & (1 << (GLYPH_W - 1 - xx))) row[gx + xx] = clock_color;
						}
					}
				}
			}
			cairo_surface_mark_dirty(p->surface);
		}
	}
blit:

	cairo_save(cr);
	cairo_scale(cr, (double)w / cols, (double)h / rows);
	cairo_set_source_surface(cr, p->surface, 0, 0);
	// NEAREST is the entire point: it preserves hard cell edges. Any other
	// filter blurs the blocks into a smooth gradient and the Ly look is gone.
	cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_NEAREST);
	cairo_paint(cr);
	cairo_restore(cr);

	// FALSE: let GtkOverlay carry on and draw window_box over the top of us.
	return FALSE;
}

static gboolean on_tick(GtkWidget *widget, GdkFrameClock *clock, gpointer data) {
	(void)clock;
	Plasma *p = data;
	if(p == NULL) return G_SOURCE_REMOVE;
	gint64 now_us = g_get_monotonic_time();
	// Frozen drops to 1fps rather than stopping outright: the block clock is
	// drawn by this same path, so removing the callback would freeze the TIME as
	// well as the plasma. 1fps is ample for a minute-resolution clock and, since
	// the cost is dominated by the per-frame blit, it is nearly free.
	gboolean frozen = anim_timeout_us > 0 && (now_us - anim_start_us) > anim_timeout_us;
	gint64 interval = frozen ? FROZEN_INTERVAL_US : render_interval_us;
	if(now_us - p->last_render_us >= interval) gtk_widget_queue_draw(widget);
	return G_SOURCE_CONTINUE;
}

// ── gtklock hooks ────────────────────────────────────────────────────────────
// Symbol names are the bare hook names; module.c looks up "on_window_create",
// not "module_on_window_create".

void on_activation(struct GtkLock *gtklock, int id) {
	(void)gtklock;
	(void)id;
	if(anim_start_us != 0) return;
	anim_start_us = g_get_monotonic_time();

	const char *env_fps = g_getenv("ATLAS_COLORMIX_FPS");
	if(env_fps != NULL) {
		int fps = atoi(env_fps);
		if(fps >= 1 && fps <= 120) render_interval_us = G_USEC_PER_SEC / fps;
	}
	const char *env_timeout = g_getenv("ATLAS_COLORMIX_TIMEOUT_SEC");
	if(env_timeout != NULL) {
		int secs = atoi(env_timeout);
		if(secs > 0) anim_timeout_us = (gint64)secs * G_USEC_PER_SEC;
	}
	const char *env_cw = g_getenv("ATLAS_COLORMIX_CELL_W");
	if(env_cw != NULL) {
		int v = atoi(env_cw);
		if(v >= 1 && v <= 128) cell_w = v;
	}
	const char *env_ch = g_getenv("ATLAS_COLORMIX_CELL_H");
	if(env_ch != NULL) {
		int v = atoi(env_ch);
		if(v >= 1 && v <= 128) cell_h = v;
	}

	// Ly rerolls these per launch (ColorMix.zig:52-53), so every lock shows a
	// different composition. Matching that is deliberate.
	pattern_cos_mod = (float)(g_random_double() * G_PI * 2.0);
	pattern_sin_mod = (float)(g_random_double() * G_PI * 2.0);
	build_palette();
}

void on_window_create(struct GtkLock *gtklock, struct Window *win) {
	(void)gtklock;
	if(win == NULL || win->overlay == NULL) return;
	if(anim_start_us == 0) on_activation(NULL, 0);   // defensive: hook order

	Plasma *p = g_malloc0(sizeof(Plasma));
	p->clock_label = win->clock_label;
	// Owned by the overlay: freed automatically when the window goes away, so
	// on_window_destroy has nothing to chase.
	g_object_set_data_full(G_OBJECT(win->overlay), "atlas-colormix", p, plasma_free);

	// Connected NOT-after, so we paint before GtkOverlay draws its children and
	// window_box lands on top of the plasma rather than under it.
	g_signal_connect(win->overlay, "draw", G_CALLBACK(on_overlay_draw), p);
	gtk_widget_add_tick_callback(win->overlay, on_tick, p, NULL);
}
