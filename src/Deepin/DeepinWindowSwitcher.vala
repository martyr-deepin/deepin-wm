//
//  Copyright (C) 2014 Deepin, Inc.
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

using Clutter;
using Meta;

namespace Gala
{
	public class DeepinWindowSwitcher : Clutter.Actor
	{
		const int POPUP_DELAY_TIMEOUT = 150; // milliseconds, keep popup window hidden when clicked alt-tab quickly
		const int MIN_DELTA = 100; // milliseconds, repeat key pressing minimum delta time after popup shown
		const int POPUP_SCREEN_PADDING = 20;
		const int POPUP_PADDING = 36;

		public WindowManager wm { get; construct; }

		static Gtk.StyleContext? style_context = null;

		DeepinWindowSwitcherItem? current_item = null;

		Actor popup;
		Actor item_container;
		Actor window_clones;
		List<Actor> clone_sort_order;

		uint popup_delay_timeout_id = 0;

		uint modifier_mask;
		int64 last_switch_time = 0;
		bool closing = false;
		ModalProxy modal_proxy;

		public DeepinWindowSwitcher (WindowManager wm)
		{
			Object (wm: wm);
		}

		construct
		{
			if (style_context == null) {
				style_context = DeepinUtils.new_css_style_context("deepin-window-switcher");
			}

			popup = new Actor ();
			popup.opacity = 0;

			var layout = new BoxLayout ();
			layout.orientation = Orientation.HORIZONTAL;
			popup.layout_manager = layout;

			var popup_canvas = new Canvas ();
			popup_canvas.draw.connect (on_draw_popup_background);

			popup.content = popup_canvas;
			popup.notify["allocation"].connect (() =>
				popup_canvas.set_size ((int) popup.width, (int) popup.height));

			item_container = new Actor ();
			item_container.margin_bottom = POPUP_PADDING;
			item_container.margin_left = POPUP_PADDING;
			item_container.margin_right = POPUP_PADDING;
			item_container.margin_top = POPUP_PADDING;
			item_container.layout_manager = new DeepinWindowSwitcherLayout ();

			item_container.actor_removed.connect (on_item_removed);
			popup.add_child (item_container);

			window_clones = new Actor ();
			window_clones.actor_removed.connect (on_clone_removed);

			add_child (window_clones);
			add_child (popup);

			wm.get_screen ().monitors_changed.connect (on_monitor_changed);

			visible = false;
		}

		~DeepinWindowSwitcher ()
		{
			if (popup_delay_timeout_id != 0) {
				Source.remove (popup_delay_timeout_id);
			}

			wm.get_screen ().monitors_changed.disconnect (on_monitor_changed);
		}

		/**
		 * set the values which don't get set every time and need to
		 * be updated when the monitor changes
		 */
		void on_monitor_changed ()
		{
			place_popup ();
		}

		bool on_draw_popup_background (Cairo.Context cr, int width, int height)
		{
			// fix size
			if (width <= 0 || height <= 0) {
				width = 1;
				height = 1;
			}

			// clear content
			cr.set_operator (Cairo.Operator.CLEAR);
			cr.paint ();
			cr.set_operator (Cairo.Operator.OVER);

			style_context.render_background (cr, 0, 0, width, height);
			style_context.render_frame (cr, 0, 0, width, height);

			return false;
		}

		void place_popup ()
		{
			var geometry = get_screen_geometry ();

			var switcher_layout = item_container.layout_manager as DeepinWindowSwitcherLayout;
			switcher_layout.max_width = geometry.width - POPUP_SCREEN_PADDING * 2 - POPUP_PADDING * 2;;

			popup.x = Math.ceilf (geometry.x + (geometry.width - popup.width) / 2.0f);
			popup.y = Math.ceilf (geometry.y + (geometry.height - popup.height) / 2.0f);
		}
		Meta.Rectangle get_screen_geometry ()
		{
			var screen = wm.get_screen ();
			return screen.get_monitor_geometry (screen.get_primary_monitor ());
		}

		void show_popup ()
		{
			popup.opacity = 255;
		}

		void hide_popup ()
		{
			popup.opacity = 0;
		}

		bool on_clicked_item (Clutter.ButtonEvent event) {
			unowned DeepinWindowSwitcherItem item = (DeepinWindowSwitcherItem) event.source;

			if (current_item != item) {
				current_item = item;
				dim_items ();

				// wait for the dimming to finish
				Timeout.add (250, () => {
					close (wm.get_screen ().get_display ().get_current_time ());
					return false;
				});
			} else {
				close (event.time);
			}

			return true;
		}

		void on_clone_removed (Actor actor)
		{
			clone_sort_order.remove (actor);
		}

		void on_item_removed (Actor actor)
		{
			if (item_container.get_n_children () == 1) {
				close (wm.get_screen ().get_display ().get_current_time ());
				return;
			}

			if (actor == current_item) {
				current_item = (DeepinWindowSwitcherItem) current_item.get_next_sibling ();
				if (current_item == null) {
					current_item = (DeepinWindowSwitcherItem) item_container.get_first_child ();
				}

				dim_items ();
			}

			place_popup ();
		}

		public override bool key_release_event (Clutter.KeyEvent event)
		{
			if ((get_current_modifiers () & modifier_mask) == 0) {
				close (event.time);
			}

			return true;
		}

		public override void key_focus_out ()
		{
			close (wm.get_screen ().get_display ().get_current_time ());
		}

		[CCode (instance_pos = -1)]
		public void handle_switch_windows (Display display, Screen screen, Window? window,
#if HAS_MUTTER314
			Clutter.KeyEvent event, KeyBinding binding)
#else
			X.Event event, KeyBinding binding)
#endif
		{
			var now = get_monotonic_time () / 1000;
			if (now - last_switch_time < MIN_DELTA) {
				return;
			}

			// if we were still closing while the next invocation comes in, we need to cleanup
			// things right away
			if (visible && closing) {
				close_cleanup ();
			}

			last_switch_time = now;

			var workspace = screen.get_active_workspace ();
			var binding_name = binding.get_name ();
			var backward = binding_name.has_suffix ("-backward");

			// FIXME for unknown reasons, switch-applications-backward won't be emitted, so we
			//       test manually if shift is held down
			if (binding_name == "switch-applications") {
				backward = (get_current_modifiers () & ModifierType.SHIFT_MASK) != 0;
			}

			if (visible && !closing) {
				current_item = next_item (workspace, backward);
				dim_items ();
				return;
			}

			var window_type = TabList.NORMAL;
			if (binding_name == "switch-group" || binding_name == "switch-group-backward") {
				window_type = TabList.GROUP;
			}
			if (!collect_windows (workspace, window_type)) {
				return;
			}

			set_primary_modifier (binding.get_mask ());

			current_item = next_item (workspace, backward);

			place_popup ();

			visible = true;
			closing = false;
			modal_proxy = wm.push_modal ();
			modal_proxy.keybinding_filter = (binding) => {
				// if it's not built-in, we can block it right away
				if (!binding.is_builtin ()) {
					return true;
				}

				// otherwise we determine by name if it's meant for us
				var name = binding.get_name ();

				return !(name == "switch-applications" || name == "switch-applications-backward"
						 || name == "switch-windows" || name == "switch-windows-backward"
						 || name == "switch-group" || name == "switch-group-backward");
			};

			dim_items ();
			grab_key_focus ();

			if ((get_current_modifiers () & modifier_mask) == 0) {
				close (wm.get_screen ().get_display ().get_current_time ());
			}

			// We delay showing the popup so that fast Alt+Tab users aren't
			// disturbed by the popup briefly flashing.
			if (popup_delay_timeout_id != 0) {
				Source.remove (popup_delay_timeout_id);
			}
			popup_delay_timeout_id = Timeout.add (POPUP_DELAY_TIMEOUT, () => {
				if (visible && !closing) {
					show_clones ();
					hide_windows (workspace);
					dim_items ();
					show_popup ();
				}
				popup_delay_timeout_id = 0;
				return false;
			});
		}

		void close_cleanup ()
		{
			item_container.destroy_all_children ();

			visible = false;
			closing = false;

			window_clones.destroy_all_children ();

			restore_windows ();
		}

		void close (uint time)
		{
			if (closing) {
				return;
			}

			closing = true;
			last_switch_time = 0;

			foreach (var actor in clone_sort_order) {
				unowned SafeWindowClone clone = (SafeWindowClone) actor;

				// current clone stays on top
				if (clone.window == current_item.window) {
					continue;
				}

				// reset order
				window_clones.set_child_below_sibling (clone, null);

				if (!clone.window.minimized) {
					clone.save_easing_state ();
					clone.set_easing_duration (150);
					clone.set_easing_mode (AnimationMode.EASE_OUT_CUBIC);

					clone.z_position = 0;
					clone.opacity = 255;

					clone.restore_easing_state ();
				}
			}

			if (current_item != null) {
				current_item.window.activate (time);
				current_item = null;
			}

			wm.pop_modal (modal_proxy);

			set_child_above_sibling (popup, null);

			hide_popup ();

			var transition = popup.get_transition ("opacity");
			if (transition != null) {
				transition.completed.connect (() => close_cleanup ());
			} else {
				close_cleanup ();
			}
		}

		/**
		 * Adds the suitable windows on the given workspace to the switcher
		 *
		 * @return whether the switcher should actually be started or if there are
		 *         not enough windows
		 */
		bool collect_windows (Workspace workspace, TabList type)
		{
			var screen = workspace.get_screen ();
			var display = screen.get_display ();

#if HAS_MUTTER314
			var windows = display.get_tab_list (type, workspace);
			var current = display.get_tab_current (type, workspace);
#else
			var windows = display.get_tab_list (type, screen, workspace);
			var current = display.get_tab_current (type, screen, workspace);
#endif

			if (windows.length () < 1) {
				return false;
			}

			if (windows.length () == 1) {
				var window = windows.data;
				if (window.minimized) {
					window.unminimize ();
				}

				window.activate (display.get_current_time ());

				return false;
			}

			foreach (var window in windows) {
				var item = add_item (window);
				if (window == current) {
					current_item = item;
				}
			}

			clone_sort_order = window_clones.get_children ().copy ();

			if (current_item == null) {
				current_item = (DeepinWindowSwitcherItem) item_container.get_child_at_index (0);
			}

			return true;
		}

		DeepinWindowSwitcherItem? add_item (Window window)
		{
			var actor = window.get_compositor_private () as WindowActor;
			if (actor == null) {
				return null;
			}

			var safe_clone = new SafeWindowClone (window, true);
			safe_clone.x = actor.x;
			safe_clone.y = actor.y;
			safe_clone.opacity = 0; // keepin hidden before popup window shown

			window_clones.add_child (safe_clone);

			var item = new DeepinWindowSwitcherItem (window);
			item.reactive = true;
			item.button_release_event.connect (on_clicked_item);

			item_container.add_child (item);

			return item;
		}

		DeepinWindowSwitcherItem next_item (Workspace workspace, bool backward)
		{
			Actor actor;
			if (!backward) {
				actor = current_item.get_next_sibling ();
				if (actor == null) {
					actor = item_container.get_first_child ();
				}
			} else {
				actor = current_item.get_previous_sibling ();
				if (actor == null) {
					actor = item_container.get_last_child ();
				}
			}

			return (DeepinWindowSwitcherItem) actor;
		}


		void dim_items ()
		{
			// show animation only when popup window shown
			bool animate = (popup.visible && popup.opacity != 0) ? true : false;

			var window_opacity = (int) Math.floor (AppearanceSettings.get_default ().alt_tab_window_opacity * 255);

			foreach (var actor in window_clones.get_children ()) {
				unowned SafeWindowClone clone = (SafeWindowClone) actor;

				actor.save_easing_state ();
				actor.set_easing_duration (animate ? 250 : 0);
				actor.set_easing_mode (AnimationMode.EASE_OUT_QUAD);

				if (clone.window == current_item.window) {
					window_clones.set_child_above_sibling (actor, null);
					actor.z_position = 0;
					actor.opacity = 255;
				} else {
					actor.z_position = -200;
					actor.opacity = window_opacity;
				}

				actor.restore_easing_state ();
			}

			foreach (var actor in item_container.get_children ()) {
				unowned DeepinWindowSwitcherItem item = (DeepinWindowSwitcherItem) actor;
				if (item == current_item) {
					item.select (true, animate);
				} else {
					item.select (false, animate);
				}
			}
		}

		void show_clones ()
		{
			foreach (var actor in window_clones.get_children ()) {
				actor.opacity = 255;
			}
		}

		void hide_windows (Workspace workspace)
		{
			var screen = workspace.get_screen ();
			foreach (var actor in Compositor.get_window_actors (screen)) {
				var window = actor.get_meta_window ();
				var type = window.window_type;

				if (type != WindowType.DOCK
					&& type != WindowType.DESKTOP
					&& type != WindowType.NOTIFICATION) {
					actor.hide ();
				}
			}
		}

		void restore_windows ()
		{
			var screen = wm.get_screen ();
			var workspace = screen.get_active_workspace ();

			// need to go through all the windows because of hidden dialogs
			unowned List<WindowActor>? window_actors = Compositor.get_window_actors (screen);
			foreach (var actor in window_actors) {
				unowned Window window = actor.get_meta_window ();

				if (window.get_workspace () == workspace
					&& window.showing_on_its_workspace ()) {
					actor.show ();
				}
			}
		}

		/**
		 * copied from gnome-shell, finds the primary modifier in the mask and saves it
		 * to our modifier_mask field
		 *
		 * @param mask The modifier mask to extract the primary one from
		 */
		void set_primary_modifier (uint mask)
		{
			if (mask == 0) {
				modifier_mask = 0;
			} else {
				modifier_mask = 1;
				while (mask > 1) {
					mask >>= 1;
					modifier_mask <<= 1;
				}
			}
		}

		Gdk.ModifierType get_current_modifiers ()
		{
			Gdk.ModifierType modifiers;
			double[] axes = {};
			Gdk.Display.get_default ().get_device_manager ().get_client_pointer ()
				.get_state (Gdk.get_default_root_window (), axes, out modifiers);

			return modifiers;
		}
	}
}
