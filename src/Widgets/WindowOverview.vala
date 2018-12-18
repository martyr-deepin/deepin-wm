//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2012 Tom Beckmann, Rico Tzschichholz
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

using Meta;
using Clutter;

namespace Gala
{

	public enum WindowOverviewType
	{
		GRID = 0,
		NATURAL
	}

	public delegate void WindowPlacer (Actor window, Meta.Rectangle rect);

	public class WindowOverview : Actor, ActivatableComponent
	{
		const int BORDER = 10;
		const int TOP_GAP = 30;
		const int BOTTOM_GAP = 30;

		public WindowManager wm { get; construct; }

		Meta.Screen screen;

		ModalProxy modal_proxy;
		bool ready;

		// the workspaces which we expose right now
		List<Workspace> workspaces;

		public WindowOverview (WindowManager wm)
		{
			Object (wm : wm);
		}

		construct
		{
			screen = wm.get_screen ();

			screen.workspace_switched.connect (close);
			screen.restacked.connect (restack_windows);

			visible = false;
			ready = true;
			reactive = true;
		}

		~WindowOverview ()
		{
			screen.restacked.disconnect (restack_windows);
		}

		public override bool key_press_event (Clutter.KeyEvent event)
		{
            bool backward = false;
            bool select = false;

			switch (event.keyval) {
			case Clutter.Key.Escape:
				close ();
				return true;

			case Clutter.Key.Return:
			case Clutter.Key.KP_Enter:
                activate_selected_window ();
                return false;
				break;

			case Clutter.Key.Tab:
			case Clutter.Key.ISO_Left_Tab:
				backward = (event.modifier_state & ModifierType.SHIFT_MASK) != 0;
                select = true;
				break;

			case Clutter.Key.Left:
			case Clutter.Key.KP_Left:
                backward = true;
                select = true;
                break;

			case Clutter.Key.Right:
			case Clutter.Key.KP_Right:
                backward = false;
                select = true;
                break;
            default:
				break;
			}

            if (select) {
                select_window_by_order (backward);
            }
			return false;
		}

		public override void key_focus_out ()
		{
			if (!contains (get_stage ().key_focus))
				close ();
		}

		public override bool button_press_event (Clutter.ButtonEvent event)
		{
			if (event.button == 1)
				close ();

			return true;
		}

		/**
		 * {@inheritDoc}
		 */
		public bool is_opened ()
		{
			return visible;
		}

		/**
		 * {@inheritDoc}
		 * You may specify 'all-windows' in hints to expose all windows
		 */
		public void open (HashTable<string,Variant>? hints = null)
		{
            Meta.verbose ("%s entry, ready = %d, visible = %d\n", Log.METHOD,
                    (int)ready, (int)visible);

			if (!ready)
				return;

			if (visible) {
				close ();
				return;
			}

			var all_windows = hints != null && "all-windows" in hints;

            var present_window_xids = new Gee.HashSet<uint32>();
            if (hints != null && "present-windows" in hints) {
                var list = hints.@get ("present-windows");
                VariantIter vi = list.iterator ();

                uint32 xid = 0;
                while (vi.next ("u", &xid)) {
                    present_window_xids.add (xid);
                    Meta.verbose ("present xid 0x%x\n", xid);
                }

                all_windows = true; // get xids from collection of all windows
            }

			var used_windows = new SList<Window> ();

			workspaces = new List<Workspace> ();

			if (all_windows) {
				foreach (var workspace in screen.get_workspaces ())
					workspaces.append (workspace);
			} else {
				workspaces.append (screen.get_active_workspace ());
			}


			foreach (var workspace in workspaces) {
				foreach (var window in workspace.list_windows ()) {
					if (window.window_type != WindowType.NORMAL &&
						window.window_type != WindowType.DOCK) {
						var actor = window.get_compositor_private () as WindowActor;
						if (actor != null) {
							actor.hide ();
                        }
						continue;
					}
					if (window.window_type == WindowType.DOCK)
						continue;

					// skip windows that are on all workspace except we're currently
					// processing the workspace it actually belongs to
					if (window.is_on_all_workspaces () && window.get_workspace () != workspace)
						continue;

                    if (present_window_xids.size > 0) {
                        if ((uint32)window.get_xwindow () in present_window_xids) {
                            used_windows.append (window);
                        } else {
                            var actor = window.get_compositor_private () as WindowActor;
                            if (actor != null) {
                                actor.hide ();
                            } 
                        }
                    } else {
                        used_windows.append (window);
                    }
				}
			}

			var n_windows = used_windows.length ();
			if (n_windows == 0) {
                cleanup ();
				return;
            }

			modal_proxy = wm.push_modal ();
			modal_proxy.keybinding_filter = keybinding_filter;
            if (!modal_proxy.grabbed) {
                Meta.verbose ("%s grab failed\n", Log.METHOD);
                wm.pop_modal (modal_proxy);
                cleanup ();
                return;
            }

            (wm as WindowManagerGala).toggle_background_blur (true);
            (wm as WindowManagerGala).polling_hotcorners ();
			ready = false;

			foreach (var workspace in workspaces) {
				workspace.window_added.connect (add_window);
				workspace.window_removed.connect (remove_window);
			}

			screen.window_left_monitor.connect (window_left_monitor);

			grab_key_focus ();

			for (var i = 0; i < screen.get_n_monitors (); i++) {
				var geometry = screen.get_monitor_geometry (i);

				var container = new DeepinWindowFlowContainer (screen.get_active_workspace ());

                unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
                var duration = animation_settings.expose_windows_duration;

                if (!animation_settings.enable_animations) {
                    duration = 0;
                }

                container.layout_duration = duration;
				container.padding_top = TOP_GAP;
				container.padding_left = container.padding_right = BORDER;
				container.padding_bottom = BOTTOM_GAP;
				container.set_position (geometry.x, geometry.y);
				container.set_size (geometry.width, geometry.height);

				container.window_activated.connect (thumb_activated);
                container.window_entered.connect (on_window_entered);

				add_child (container);
			}

			foreach (var window in used_windows) {
				unowned WindowActor actor = window.get_compositor_private () as WindowActor;
				if (actor != null)
					actor.hide ();

				unowned DeepinWindowFlowContainer container = get_child_at_index (window.get_monitor ()) as DeepinWindowFlowContainer;
				if (container == null)
					continue;

				container.add_window (window);
			}

			visible = true;

			foreach (var child in get_children ())
				((DeepinWindowFlowContainer) child).open ();

            Meta.verbose ("%s done\n", Log.METHOD);
			ready = true;
		}

		bool keybinding_filter (KeyBinding binding)
		{
			var name = binding.get_name ();
			return (name != "expose-windows" && name != "expose-all-windows");
		}

		void restack_windows (Screen screen)
		{
			foreach (var child in get_children ())
				((DeepinWindowFlowContainer) child).restack_windows (screen);
		}

		void window_left_monitor (int num, Window window)
		{
			unowned DeepinWindowFlowContainer container = get_child_at_index (num) as DeepinWindowFlowContainer;
			if (container == null)
				return;

			// make sure the window belongs to one of our workspaces
			foreach (var workspace in workspaces)
				if (window.located_on_workspace (workspace)) {
					container.remove_window (window);
					break;
				}
		}

		void add_window (Window window)
		{
			if (!visible
				|| (window.window_type != WindowType.NORMAL && window.window_type != WindowType.DIALOG))
				return;

			unowned DeepinWindowFlowContainer container = get_child_at_index (window.get_monitor ()) as DeepinWindowFlowContainer;
			if (container == null)
				return;

			// make sure the window belongs to one of our workspaces
			foreach (var workspace in workspaces)
				if (window.located_on_workspace (workspace)) {
					container.add_window (window);
					break;
				}
		}

		void remove_window (Window window)
		{
			unowned DeepinWindowFlowContainer container = get_child_at_index (window.get_monitor ()) as DeepinWindowFlowContainer;
			if (container == null)
				return;

			container.remove_window (window);

            var total = 0;
			foreach (var child in get_children ()) {
				total += ((DeepinWindowFlowContainer) child).get_n_children ();
			}

            if (total == 0) {
                close ();
            }

		}

        void on_window_entered (Window window)
        {
			unowned DeepinWindowFlowContainer container = get_child_at_index (window.get_monitor ()) as DeepinWindowFlowContainer;
			if (container == null)
				return;

            container.select_window (window, true);
        }

        void activate_selected_window ()
        {
            var monitor = screen.get_current_monitor ();
            unowned DeepinWindowFlowContainer container = get_child_at_index (monitor) as DeepinWindowFlowContainer;
            if (container == null || !container.has_selected_window ())
                return;

            thumb_activated (container.get_selected_clone ().window);
        }

		void select_window_by_order (bool backward)
		{
            var monitor = screen.get_current_monitor ();
            unowned DeepinWindowFlowContainer container = get_child_at_index (monitor) as DeepinWindowFlowContainer;
            if (container == null)
                return;
			container.select_window_by_order (backward);
		}

		void thumb_activated (Window window)
		{
			if (window.get_workspace () == screen.get_active_workspace ()) {
				window.activate (screen.get_display ().get_current_time ());
				close ();
			} else {
				close ();
				//wait for the animation to finish before switching
				Timeout.add (DeepinMultitaskingView.WORKSPACE_FADE_DURATION, () => {
					window.get_workspace ().activate_with_focus (window, screen.get_display ().get_current_time ());
					return false;
				});
			}
		}

		/**
		 * {@inheritDoc}
		 */
		public void close ()
		{
			if (!visible || !ready)
				return;

			ready = false;

            (wm as WindowManagerGala).toggle_background_blur (false);

			foreach (var workspace in workspaces) {
				workspace.window_added.disconnect (add_window);
				workspace.window_removed.disconnect (remove_window);
			}
			screen.window_left_monitor.disconnect (window_left_monitor);

			wm.pop_modal (modal_proxy);

			foreach (var child in get_children ()) {
				((DeepinWindowFlowContainer) child).close ();
			}

			Clutter.Threads.Timeout.add (300, () => {
				cleanup ();

				return false;
			});
            Meta.verbose ("%s\n", Log.METHOD);
		}

		void cleanup ()
		{
			visible = false;

            foreach (var window in screen.get_active_workspace ().list_windows ())
				if (window.showing_on_its_workspace ())
					((Actor) window.get_compositor_private ()).show ();

			destroy_all_children ();

            Meta.verbose ("%s\n", Log.METHOD);
			ready = true;
		}
	}
}
