//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
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
		// milliseconds, keep popup window hidden when clicked alt-tab quickly
		const int POPUP_DELAY_TIMEOUT = 150;

		// milliseconds, repeat key pressing minimum delta
		const int TAB_MIN_DELTA = 100;
		const int HOLDING_MIN_DELTA = 400;

		// time after popup shown
		const int POPUP_SCREEN_PADDING = 40;

		const int POPUP_PADDING = 32;

		public WindowManager wm { get; construct; }

		DeepinWindowSwitcherItem? current_item = null;

        Actor popup_border;
        Actor popup_lighter;
		Actor popup;
        BlurActor background;
		Actor item_container;
		Actor window_clones;
		Actor shape;
		List<Actor> clone_sort_order;

		uint popup_delay_timeout_id = 0;

		uint modifier_mask;
		int64 last_switch_time = 0;
        int holding_count = 0;
		bool closing = false;
		ModalProxy modal_proxy;

		public DeepinWindowSwitcher (WindowManager wm)
		{
			Object (wm: wm);
		}

		construct
		{
			var screen = wm.get_screen ();

            popup_border =
                new DeepinCssStaticActor ("deepin-window-switcher-border", Gtk.StateFlags.NORMAL);
            popup_border.set_pivot_point (0.5f, 0.5f);
            popup_border.visible = false;

            popup_lighter =
                new DeepinCssStaticActor ("deepin-window-switcher-lighter", Gtk.StateFlags.NORMAL);
            popup_lighter.set_pivot_point (0.5f, 0.5f);
            popup_border.visible = false;

            popup = new DeepinCssStaticActor ("deepin-window-switcher");
			popup.opacity = 0;

			shape = new DeepinCssStaticActor ("deepin-window-switcher-item", Gtk.StateFlags.SELECTED);
			shape.set_pivot_point (0.5f, 0.5f);
            shape.scale_x = 1.033;
            shape.scale_y = 1.033;
            shape.visible = false;

			item_container = new Actor ();
            item_container.set_name ("item_container");
            item_container.margin_bottom = POPUP_PADDING;
			item_container.margin_left = POPUP_PADDING;
            item_container.margin_right = POPUP_PADDING;
			item_container.margin_top = POPUP_PADDING;
			item_container.layout_manager = new DeepinWindowSwitcherLayout ();
            item_container.layout_manager.layout_changed.connect(update_shape_size);

			item_container.actor_removed.connect (on_item_removed);

            background = new BlurActor (screen);
            background.set_radius (15);
            background.set_name ("blur-switcher");
            background.visible = false;

			popup.add_child (item_container);

			window_clones = new Actor ();
            window_clones.set_name ("window_clones");
			window_clones.actor_removed.connect (on_clone_removed);
            window_clones.opacity = 0;

			add_child (window_clones);
            add_child (background);
            add_child (popup_lighter);
            add_child (popup_border);
            add_child (shape);
			add_child (popup);

			wm.get_screen ().monitors_changed.connect (relayout);

			visible = false;
		}

		~DeepinWindowSwitcher ()
		{
			if (popup_delay_timeout_id != 0) {
				Source.remove (popup_delay_timeout_id);
			}

			wm.get_screen ().monitors_changed.disconnect (relayout);
		}

        void update_shape_size ()
        {
            var item = item_container.get_last_child ();
            if (item == null && current_item != null) {
                item = current_item;
            }
            if (item != null) {
                var box = item.get_allocation_box ();
                float width = box.get_width (), height = box.get_height ();

                shape.set_size (width, height);
            }
        }

        private Clutter.TransitionGroup build_animation (int duration, float x, float y)
        {
            var t = new Clutter.TransitionGroup ();
            t.set_duration (duration);
            t.set_progress_mode (Clutter.AnimationMode.EASE_IN_OUT_CUBIC);

            var t1 = new Clutter.PropertyTransition ("x");
            t1.set_to_value (x);
            t.add_transition (t1);

            t1 = new Clutter.PropertyTransition ("y");
            t1.set_to_value (y);
            t.add_transition (t1);

            return t;
        }

		public void shape_move (DeepinWindowSwitcherItem? target, bool animating = true)
		{
            if (target == null) {
                return;
            }

            var box = target.get_allocation_box ();
            float tx, ty, cx, cy;
            target.get_transformed_position (out tx, out ty);
            //WTF: use transform_stage_point here cause target position incorrect, wtf!
            //transform_stage_point (tx, ty, out cx, out cy);
            cx = tx - this.x; cy = ty - this.y;

            cx += (box.x2 - box.x1)/2;
            cy += (box.y2 - box.y1)/2;

            if (animating) {
                shape.save_easing_state ();

                shape.set_easing_duration (200);
                shape.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
                shape.x = cx - shape.width / 2;
                shape.y = cy - shape.height / 2;

                shape.restore_easing_state ();
            } else {
                shape.remove_all_transitions ();
                shape.x = cx - shape.width / 2;
                shape.y = cy - shape.height / 2;
            }
		}

		public void relayout ()
        {
            var monitor_geom = DeepinUtils.get_primary_monitor_geometry (wm.get_screen ());

            set_position (monitor_geom.x, monitor_geom.y);
            set_size (monitor_geom.width, monitor_geom.height);

            var switcher_layout = item_container.layout_manager as DeepinWindowSwitcherLayout;
            var max_width = monitor_geom.width - POPUP_SCREEN_PADDING * 2 - POPUP_PADDING * 2;
            switcher_layout.max_width = max_width;
        }

        Cairo.Region? last_region = null;
		void show_popup ()
		{
            var monitor_geom = DeepinUtils.get_primary_monitor_geometry (wm.get_screen ());
            float x = Math.floorf((monitor_geom.width - popup.width) / 2);
            float y = Math.floorf((monitor_geom.height - popup.height) / 2);
            float w = Math.floorf(popup.width);
            float h = Math.floorf(popup.height);

            popup.set_position (x, y);
            background.set_position (popup.x, popup.y);
            background.set_size (w, h);

            popup_border.set_position (x-1, y-1);
            popup_border.set_size (w+2, h+2);

            popup_lighter.set_position (x, y);
            popup_lighter.set_size (w, h);

            Cairo.RectangleInt r =  {0, 0, (int)w, (int)h};
            Cairo.RectangleInt[] rects = { r };
            int[] radius = {5, 5};

            var region = new Cairo.Region.rectangles (rects);
            if (!region.equal (last_region)) {
                var blur_mask = DeepinUtils.build_blur_mask (rects, radius);
                background.set_blur_mask (blur_mask);
                last_region = region;
            }

            popup_lighter.clear_effects ();
            popup_lighter.add_effect_with_name ( "shadow",
                    new ShadowEffect ((int)popup_lighter.width, (int)popup_lighter.height, 18, 0, 30, 3));

            var referent = (DeepinWindowSwitcherWindowItem)item_container.get_child_at_index (0);
            var desktop_item = (DeepinWindowSwitcherDesktopItem)item_container.get_last_child ();
            if (referent != null && desktop_item != null)
                desktop_item.set_show_icon (referent.show_icon_only ());

            Timeout.add(10, () => {
                update_shape_size ();
                shape_move (current_item, false);
                shape.visible = true;
                return false;
            });
			popup.opacity = 255;
            window_clones.opacity = 255;
            background.visible = true;
            popup_border.visible = true;
            popup_lighter.visible = true;
		}

		void hide_popup ()
		{
            background.visible = false;
			popup.opacity = 0;
            popup_border.visible = false;
            popup_lighter.visible = false;
            shape.visible = false;
		}

		bool on_clicked_item (Clutter.ButtonEvent event)
		{
			unowned DeepinWindowSwitcherItem item = (DeepinWindowSwitcherItem)event.source;

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
				current_item = (DeepinWindowSwitcherItem)current_item.get_next_sibling ();
				if (current_item == null) {
					current_item = (DeepinWindowSwitcherItem)item_container.get_first_child ();
				}

				dim_items ();
			}
		}

		public override bool key_release_event (Clutter.KeyEvent event)
		{
			if ((get_current_modifiers () & modifier_mask) == 0) {
				close (event.time);
            }

            holding_count = 0;
			return true;
		}

		public override void key_focus_out ()
		{
			close (wm.get_screen ().get_display ().get_current_time ());
		}

		[CCode (instance_pos = -1)] public void handle_switch_windows (
			Display display, Screen screen, Window? window,
#if HAS_MUTTER314
			Clutter.KeyEvent event, KeyBinding binding)
#else
			X.Event event, KeyBinding binding)
#endif
		{
            if ((wm as WindowManagerGala).hiding_windows) 
                return;

            holding_count++;
			var now = get_monotonic_time () / 1000;
			if (holding_count > 1 && now - last_switch_time < HOLDING_MIN_DELTA) {
                return;
			} else if (holding_count <= 1 && now - last_switch_time < TAB_MIN_DELTA) {
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

			// FIXME: for unknown reasons, switch-applications-backward won't be emitted, so we test
			//        manually if shift is held down
			if (binding_name == "switch-applications") {
				backward = (get_current_modifiers () & ModifierType.SHIFT_MASK) != 0;
			}

			if (visible && !closing) {
				current_item = next_item (workspace, backward);
				dim_items ();
				return;
			}

			bool only_group_windows = false;
			if (binding_name == "switch-group" || binding_name == "switch-group-backward") {
				only_group_windows = true;
			}
			if (!collect_windows (workspace, only_group_windows)) {
				return;
			}

			set_primary_modifier (binding.get_mask ());

			current_item = next_item (workspace, backward);

			visible = true;
			closing = false;
			modal_proxy = wm.push_modal ();
			modal_proxy.keybinding_filter = (binding) =>
			{
				// if it's not built-in, we can block it right away
				if (!binding.is_builtin ()) {
					return true;
				}

				// otherwise we determine by name if it's meant for us
				var name = binding.get_name ();

				return !(name == "switch-applications" || name == "switch-applications-backward" ||
						 name == "switch-windows" || name == "switch-windows-backward" ||
						 name == "switch-group" || name == "switch-group-backward");
			};

            //dim_items ();
			grab_key_focus ();

			if ((get_current_modifiers () & modifier_mask) == 0) {
				close (wm.get_screen ().get_display ().get_current_time ());
			}

			// We delay showing the popup so that fast Alt+Tab users aren't disturbed by the popup
			// briefly flashing.
			if (popup_delay_timeout_id != 0) {
				Source.remove (popup_delay_timeout_id);
			}
			popup_delay_timeout_id = Timeout.add (POPUP_DELAY_TIMEOUT, () => {
				if (visible && !closing) {
					// add desktop item if need after popup shown
					if (BehaviorSettings.get_default ().show_desktop_in_alt_tab) {
						if (visible && !only_group_windows) {
							add_desktop_item ();
						}
					}

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
            current_item = null;

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
				unowned SafeWindowClone clone = (SafeWindowClone)actor;

				// current clone stays on top
				if (current_item is DeepinWindowSwitcherWindowItem &&
					clone.window == (current_item as DeepinWindowSwitcherWindowItem).window) {
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
				if (current_item is DeepinWindowSwitcherWindowItem) {
					(current_item as DeepinWindowSwitcherWindowItem).window.activate (time);
				} else {
					DeepinUtils.show_desktop (wm.get_screen ().get_active_workspace ());
				}
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
		 * @return whether the switcher should actually be started or if there are not enough
		 *         windows
		 */
		bool collect_windows (Workspace workspace, bool only_group_windows)
		{
			var screen = workspace.get_screen ();
			var display = screen.get_display ();

#if HAS_MUTTER314
			var all_windows = display.get_tab_list (TabList.NORMAL, workspace);
			var current = display.get_tab_current (TabList.NORMAL, workspace);
#else
			var all_windows = display.get_tab_list (TabList.NORMAL, screen, workspace);
			var current = display.get_tab_current (TabList.NORMAL, screen, workspace);
#endif

			// FIXME: We must filter some windows that do not shown in current workspace manually,
			//        this should be a bug of mutter.
			// Reproduct:
			// 1. open xfce4-terminal(0.6.3) in workspace 1
			// 2. switch to the empty workspace 2, and open another two xfce4-terminal process
			// 3. press alt-tab in workspace 1 and it will show three xfce4-terminal items
			var fixed_all_windows = new GLib.List<weak Meta.Window> ();
			foreach (var window in all_windows) {
				if (window.get_workspace () == workspace) {
					fixed_all_windows.append (window);
				}
			}

			GLib.List<weak Meta.Window> windows;
			if (!only_group_windows) {
				windows = fixed_all_windows.copy ();
			} else {
				windows = new GLib.List<weak Meta.Window> ();
				foreach (var window in fixed_all_windows) {
					if (window.wm_class == current.wm_class) {
						windows.append (window);
					}
				}
			}

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
				current_item = (DeepinWindowSwitcherItem)item_container.get_child_at_index (0);
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
			safe_clone.x = actor.x - this.x;
			safe_clone.y = actor.y - this.y;
			safe_clone.opacity = 0;  // keepin hidden before popup window shown

			window_clones.add_child (safe_clone);

			var item = new DeepinWindowSwitcherWindowItem (window);
			item.reactive = true;
			item.button_release_event.connect (on_clicked_item);

			item_container.add_child (item);

			return item;
		}

		void add_desktop_item ()
		{
			var item = new DeepinWindowSwitcherDesktopItem (wm.get_screen ());
			item.reactive = true;
			item.button_release_event.connect (on_clicked_item);

            var referent = (DeepinWindowSwitcherWindowItem)item_container.get_child_at_index (0);
            referent.notify["allocation"].connect(() => {
                item.set_show_icon (referent.show_icon_only ());
            });

			item_container.add_child (item);
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

			return (DeepinWindowSwitcherItem)actor;
		}

		void dim_items ()
		{
			// show animation only when popup window shown
			bool animate = (popup.visible && popup.opacity != 0) ? true : false;

			var window_opacity =
				(int)Math.floor (AppearanceSettings.get_default ().alt_tab_window_opacity * 255);
            
            foreach (var child in window_clones.get_children ()) {
                var clone = child as SafeWindowClone;

                clone.save_easing_state ();
                clone.set_easing_duration (animate ? 250 : 0);
                clone.set_easing_mode (AnimationMode.EASE_OUT_QUAD);

                if (current_item is DeepinWindowSwitcherWindowItem) {
                    if (clone.window == (current_item as DeepinWindowSwitcherWindowItem).window) {
                        window_clones.set_child_above_sibling (clone, null);
                        clone.z_position = 0;
                        clone.opacity = 255;
                    } else {
                        clone.z_position = -200;
                        clone.opacity = window_opacity;
                    }
                } else {
                    // when desktop item selected, hide all clones
                    clone.z_position = -200;
                    clone.opacity = 0;
                }

                clone.restore_easing_state ();
            }

            if (current_item != null)
                shape_move (current_item);
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

				if (type != WindowType.DOCK && type != WindowType.DESKTOP &&
					type != WindowType.NOTIFICATION) {
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

				if (window.get_workspace () == workspace && window.showing_on_its_workspace ()) {
                    actor.show ();
				}
			}
		}

		/**
		 * copied from gnome-shell, finds the primary modifier in the mask and saves it to our
		 * modifier_mask field
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
			Gdk.Display.get_default ().get_device_manager ().get_client_pointer ().get_state (
				Gdk.get_default_root_window (), axes, out modifiers);

			return modifiers;
		}
	}
}
