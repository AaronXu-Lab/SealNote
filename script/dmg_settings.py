from pathlib import Path

root = Path.cwd()
format = "UDZO"
filesystem = "HFS+"
files = [str(root / ".build/dmg-stage/Seal Note.app")]
symlinks = {"Applications": "/Applications"}
icon_locations = {"Seal Note.app": (190, 225), "Applications": (610, 225)}
background = str(root / ".build/dmg-art/background.tiff")
icon = str(root / ".build/dmg-art/SealNote.icns")
window_rect = ((240, 160), (800, 440))
icon_size = 180
text_size = 16
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_sidebar = False
show_pathbar = False
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
hide_extensions = []
