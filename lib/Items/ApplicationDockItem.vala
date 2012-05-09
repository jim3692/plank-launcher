//  
//  Copyright (C) 2011-2012 Robert Dyer, Rico Tzschichholz
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

using Gdk;
using Gee;
using Gtk;

using Plank.Drawing;
using Plank.Services;
using Plank.Services.Windows;

namespace Plank.Items
{
	/**
	 * A dock item for applications (with .desktop launchers).
	 */
	public class ApplicationDockItem : DockItem
	{
		// for the Unity static quicklists
		// see https://wiki.edubuntu.org/Unity/LauncherAPI#Static_Quicklist_entries
		private const string UNITY_QUICKLISTS_KEY = "X-Ayatana-Desktop-Shortcuts";
		private const string UNITY_QUICKLISTS_SHORTCUT_GROUP_NAME = "%s Shortcut Group";
		private const string UNITY_QUICKLISTS_TARGET_KEY = "TargetEnvironment";
		private const string UNITY_QUICKLISTS_TARGET_VALUE = "Unity";
		private const string UNITY_QUICKLISTS_NAME_KEY = "Name";
		private const string UNITY_QUICKLISTS_EXEC_KEY = "Exec";
		
		/**
		 * Signal fired when the item's 'keep in dock' menu item is pressed.
		 */
		public signal void pin_launcher ();
		
		/**
		 * Signal fired when the application associated with this item closes.
		 */
		public signal void app_closed ();
		
		internal Bamf.Application? App { get; private set; default = null; }
		
		ArrayList<string> shortcuts = new ArrayList<string> ();
		HashMap<string, string> shortcut_map = new HashMap<string, string> (str_hash, str_equal);
		
		/**
		 * {@inheritDoc}
		 */
		public ApplicationDockItem.with_dockitem_file (GLib.File file)
		{
			Prefs = new DockItemPreferences.with_file (file);
			
			initialize ();
		}
		
		/**
		 * {@inheritDoc}
		 */
		public ApplicationDockItem.with_dockitem_filename (string filename)
		{
			Prefs = new DockItemPreferences.with_filename (filename);
			
			initialize ();
		}
		
		void initialize ()
		{
			if (!ValidItem)
				return;
			
			Prefs.changed["Launcher"].connect (handle_launcher_changed);
			Prefs.deleted.connect (handle_deleted);
			
			load_from_launcher ();
		}
		
		~ApplicationDockItem ()
		{
			Prefs.changed["Launcher"].disconnect (handle_launcher_changed);
			Prefs.deleted.disconnect (handle_deleted);
			
			unset_app ();
			stop_monitor ();
		}
		
		internal void set_app (Bamf.Application? app)
		{
			if (app == null || App == app)
				return;
			
			unset_app ();
			
			App = app;
			
			App.active_changed.connect (handle_active_changed);
			App.running_changed.connect (handle_running_changed);
			App.urgent_changed.connect (handle_urgent_changed);
			App.window_added.connect (handle_window_added);
			App.window_removed.connect (handle_window_removed);
			App.closed.connect (handle_closed);
			
			initialize_states ();
		}
		
		void unset_app ()
		{	
			if (App == null)
				return;
			
			App.active_changed.disconnect (handle_active_changed);
			App.running_changed.disconnect (handle_running_changed);
			App.urgent_changed.disconnect (handle_urgent_changed);
			App.window_added.disconnect (handle_window_added);
			App.window_removed.disconnect (handle_window_removed);
			App.closed.disconnect (handle_closed);
			
			App = null;
		}
		
		void initialize_states ()
			requires (App != null)
		{
			handle_active_changed (App.is_active ());
			handle_urgent_changed (App.is_urgent ());
			
			update_indicator (WindowControl.get_num_windows (App));
		}
		
		public bool is_running ()
		{
			return (App != null && App.is_running ());
		}
		
		public bool is_window ()
		{
			return (App != null && App.get_desktop_file () == "");
		}
		
		void handle_launcher_changed ()
		{
			unset_app ();
			set_app (Matcher.get_default ().app_for_launcher (Prefs.Launcher));
			
			launcher_changed ();
		}
		
		void handle_closed ()
		{
			if (this is TransientDockItem)
				unset_app ();
			
			handle_urgent_changed (false);
			handle_active_changed (false);
			update_indicator (0);
			
			app_closed ();
		}
		
		void handle_active_changed (bool is_active)
		{
			var was_active = (State & ItemState.ACTIVE) == ItemState.ACTIVE;
			
			if (is_active && !was_active) {
				LastActive = new DateTime.now_utc ();
				State |= ItemState.ACTIVE;
			} else if (!is_active && was_active) {
				LastActive = new DateTime.now_utc ();
				State &= ~ItemState.ACTIVE;
			}
		}
		
		void handle_running_changed (bool is_running)
		{
			if (is_running)
				return;
			
			handle_urgent_changed (false);
			handle_active_changed (false);
			update_indicator (0);
		}
		
		void handle_urgent_changed (bool is_urgent)
		{
			var was_urgent = (State & ItemState.URGENT) == ItemState.URGENT;
			
			if (is_urgent && !was_urgent) {
				LastUrgent = new DateTime.now_utc ();
				State |= ItemState.URGENT;
			} else if (!is_urgent && was_urgent) {
				State &= ~ItemState.URGENT;
			}
		}
		
		void handle_window_added (Bamf.View? child)
		{
			update_indicator (WindowControl.get_num_windows (App));
		}
		
		void handle_window_removed (Bamf.View? child)
		{
			update_indicator (WindowControl.get_num_windows (App));
		}
		
		void update_indicator (uint window_count)
		{
			if (window_count == 0) {
				if (Indicator != IndicatorState.NONE)
					Indicator = IndicatorState.NONE;
			} else if (window_count == 1) {
				if (Indicator != IndicatorState.SINGLE)
					Indicator = IndicatorState.SINGLE;
			} else {
				if (Indicator != IndicatorState.SINGLE_PLUS)
					Indicator = IndicatorState.SINGLE_PLUS;
			}
		}
		
		void launch ()
		{
			Services.System.launch (File.new_for_path (Prefs.Launcher));
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override ClickAnimation on_clicked (PopupButton button, ModifierType mod)
		{
			if (!is_window ())
				if (button == PopupButton.MIDDLE || 
					(button == PopupButton.LEFT && (App == null || WindowControl.get_num_windows (App) == 0 ||
					(mod & ModifierType.CONTROL_MASK) == ModifierType.CONTROL_MASK))) {
					launch ();
					return ClickAnimation.BOUNCE;
				}
			
			if (button == PopupButton.LEFT && App != null && WindowControl.get_num_windows (App) > 0) {
				WindowControl.smart_focus (App);
				return ClickAnimation.DARKEN;
			}
			
			return ClickAnimation.NONE;
		}
		
		/**
		 * {@inheritDoc}
		 */
		protected override void on_scrolled (ScrollDirection direction, ModifierType mod)
		{
			if (App == null || WindowControl.get_num_windows (App) == 0 ||
				(new DateTime.now_utc ().difference (LastScrolled) < WindowControl.VIEWPORT_CHANGE_DELAY * 1000))
				return;
			
			LastScrolled = new DateTime.now_utc ();
			
			if (direction == ScrollDirection.UP || direction == ScrollDirection.LEFT)
				WindowControl.focus_previous (App);
			else
				WindowControl.focus_next (App);
		}
		
		/**
		 * {@inheritDoc}
		 */
		public override ArrayList<Gtk.MenuItem> get_menu_items ()
		{
			var items = new ArrayList<Gtk.MenuItem> ();
			
			GLib.List<unowned Bamf.View>? windows = null;
			if (App != null)
				windows = App.get_windows ();
			
			if (!is_window ()) {
				var item = new CheckMenuItem.with_mnemonic (_("_Keep in Dock"));
				item.active = !(this is TransientDockItem);
				item.activate.connect (() => pin_launcher ());
				items.add (item);
			}
			
			if (is_running () && windows != null && windows.length () > 0) {
				Gtk.MenuItem item;
				
				if (WindowControl.has_maximized_window (App)) {
					item = create_menu_item (_("Unma_ximize"), "view-fullscreen");
					item.activate.connect (() => WindowControl.unmaximize (App));
					items.add (item);
				} else {
					item = create_menu_item (_("Ma_ximize"), "view-fullscreen");
					item.activate.connect (() => WindowControl.maximize (App));
					items.add (item);
				}
				
				item = create_menu_item (_("_Close All"), "window-close-symbolic;;window-close");
				item.activate.connect (() => WindowControl.close_all (App));
				items.add (item);
			}
			
			if (!is_window () && shortcuts.size > 0) {
				items.add (new SeparatorMenuItem ());
				
				foreach (var s in shortcuts) {
					var item = new Gtk.MenuItem.with_mnemonic (s);
					item.activate.connect (() => {
						try {
							AppInfo.create_from_commandline (shortcut_map.get (s), null, AppInfoCreateFlags.NONE).launch (null, null);
						} catch { }
					});
					items.add (item);
				}
			}
			
			if (is_running () && windows != null && windows.length () > 0) {
				items.add (new SeparatorMenuItem ());
				
				int width, height;
				icon_size_lookup (IconSize.MENU, out width, out height);
				
				foreach (var view in windows) {
					var window = (view as Bamf.Window);
					if (window == null)
						continue;
					
					var pbuf = WindowControl.get_window_icon (window);
					if (pbuf == null)
						pbuf = DrawingService.load_icon (Icon, width, height);
					else
						pbuf = DrawingService.ar_scale (pbuf, width, height);
					
					var window_item = new ImageMenuItem.with_mnemonic (window.get_name ());
					window_item.set_image (new Gtk.Image.from_pixbuf (pbuf));
					window_item.activate.connect (() => WindowControl.focus_window (window));
					items.add (window_item);
				}
			}
			
			return items;
		}
		
		/**
		 * Parses the associated launcher and sets the icon and text from it.
		 */
		protected void load_from_launcher ()
		{
			stop_monitor ();
			
			string icon, text;
			parse_launcher (Prefs.Launcher, out icon, out text, shortcuts, shortcut_map);
			Icon = icon;
			ForcePixbuf = null;
			Text = text;
			
			start_monitor ();
		}
		
		/**
		 * Parses a launcher to get the text, icon and Unity static quicklist shortcuts.
		 *
		 * @param launcher the launcher file (.desktop file) to parse
		 * @param icon the icon key from the launcher
		 * @param text the text key from the launcher
		 * @param shortcuts a list of all Unity static quicklist shortcuts by name
		 * @param shortcut_map a map of Unity static quicklist shortcuts from name to exec
		 */
		public static void parse_launcher (string launcher, out string icon, out string text, ArrayList<string>? shortcuts, HashMap<string, string>? shortcut_map)
		{
			icon = "";
			text = "";
			
			try {
				var file = new KeyFile ();
				file.load_from_file (launcher, 0);
				
				icon = file.get_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
				text = file.get_locale_string (KeyFileDesktop.GROUP, KeyFileDesktop.KEY_NAME);
				
				// get the Unity static quicklists
				// see https://wiki.edubuntu.org/Unity/LauncherAPI#Static Quicklist entries
				if (shortcuts != null && shortcut_map != null) {
					shortcuts.clear ();
					shortcut_map.clear ();
					
					if (file.has_key (KeyFileDesktop.GROUP, UNITY_QUICKLISTS_KEY))
						foreach (var shortcut in file.get_string_list (KeyFileDesktop.GROUP, UNITY_QUICKLISTS_KEY)) {
							var group = UNITY_QUICKLISTS_SHORTCUT_GROUP_NAME.printf (shortcut);
							if (!file.has_group (group))
								continue;
							
							// check for TargetEnvironment
							if (file.has_key (group, UNITY_QUICKLISTS_TARGET_KEY)) {
								var target = file.get_string (group, UNITY_QUICKLISTS_TARGET_KEY);
								if (target != UNITY_QUICKLISTS_TARGET_VALUE && target != "Plank")
									continue;
							}
							
							// check for OnlyShowIn
							if (file.has_key (group, "OnlyShowIn")) {
								var found = false;
								
								foreach (var s in file.get_string_list (group, "OnlyShowIn"))
									if (s == UNITY_QUICKLISTS_TARGET_VALUE || s == "Plank") {
										found = true;
										break;
									}
								
								if (!found)
									continue;
							}
							
							var name = file.get_locale_string (group, UNITY_QUICKLISTS_NAME_KEY);
							shortcuts.add (name);
							shortcut_map.set (name, file.get_string (group, UNITY_QUICKLISTS_EXEC_KEY));
						}
				}
			} catch { }
		}
		
		FileMonitor? monitor = null;
		
		void start_monitor ()
		{
			if (monitor != null)
				return;
			
			try {
				monitor = File.new_for_path (Prefs.Launcher).monitor (0);
				monitor.changed.connect (monitor_changed);
			} catch {
				warning ("Unable to watch the launcher file '%s'", Prefs.Launcher);
			}
		}
		
		void monitor_changed (File f, File? other, FileMonitorEvent event)
		{
			if ((event & FileMonitorEvent.CHANGES_DONE_HINT) != FileMonitorEvent.CHANGES_DONE_HINT &&
				(event & FileMonitorEvent.DELETED) != FileMonitorEvent.DELETED)
				return;
			
			debug ("Launcher file '%s' changed, reloading", Prefs.Launcher);
			load_from_launcher ();
		}
		
		void stop_monitor ()
		{
			if (monitor == null)
				return;
			
			monitor.changed.disconnect (monitor_changed);
			monitor.cancel ();
			monitor = null;
		}
	}
}
