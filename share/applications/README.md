# Desktop-entry overrides

Files here are `NoDisplay=true` stubs that shadow a system `.desktop` of the
same name, hiding it from the rofi launcher without touching `/usr`.

XDG resolves an application id by scanning `XDG_DATA_DIRS` in order, and
`~/.local/share/applications` comes first -- so a stub with a matching filename
wins over `/usr/share/applications/<same>.desktop`. The system copy is never
edited, so a package update cannot revert this and nothing breaks if the
package is removed.

Each stub keeps `Name` and `Exec` so the entry is still valid and still
launchable by id; it is only hidden from menus.
