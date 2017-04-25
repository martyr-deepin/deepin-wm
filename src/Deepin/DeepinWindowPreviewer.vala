//
//  Copyright (C) 2016 Deepin Technology Co., Ltd.
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
	public class WindowPreviewer : Actor
	{
		public WindowManager wm { get; construct; }

		Meta.Screen screen;

		ModalProxy modal_proxy;
		bool ready;

        Meta.Window? target_window = null;

		List<Workspace> workspaces;

		public WindowPreviewer (WindowManager wm)
		{
			Object (wm : wm);
		}

		construct
		{
			screen = wm.get_screen ();

			screen.workspace_switched.connect (close);
            screen.monitors_changed.connect (update_previewer);

			visible = false;
			ready = true;
			reactive = true;
		}

		~WindowPreviewer ()
		{
		}

		public override bool key_press_event (Clutter.KeyEvent event)
		{
			if (event.keyval == Clutter.Key.Escape) {
				close ();

				return true;
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

		public bool is_opened ()
		{
			return visible;
		}

        Meta.Window? find_window_by_xid (uint32 xid)
        {
            foreach (var workspace in workspaces) {
                foreach (var window in workspace.list_windows ()) {
                    if ((uint32)window.get_xwindow () == xid) {
                        return window;
                    }
                }
			}

            return null;
        }

        public void change_preview (uint32 xid)
        {
            int duration = 500;

            if (target_window != null) {
                //fade out
                var actor = target_window.get_compositor_private () as WindowActor;
                target_window = null;
                //actor.remove_all_transitions ();

                actor.show ();
                actor.opacity = 255;

				actor.save_easing_state ();
				actor.set_easing_mode (Clutter.AnimationMode.LINEAR);
				actor.set_easing_duration (duration);
                actor.opacity = 0;
				actor.restore_easing_state ();

                ulong handler_id = 0UL;
				handler_id = actor.transition_stopped.connect (() => {
                    actor.disconnect (handler_id);
                    actor.hide ();
                    actor.opacity = 255;
				});
            }

            target_window = find_window_by_xid (xid);
            if (target_window != null) {
                var actor = target_window.get_compositor_private () as WindowActor;
                //actor.remove_all_transitions ();

                int n = target_window.get_monitor();
                var geometry = screen.get_monitor_geometry (n);

                actor.opacity = 0;
                actor.show ();
				actor.save_easing_state ();
				actor.set_easing_mode (Clutter.AnimationMode.LINEAR);
				actor.set_easing_duration (duration);
                actor.opacity = 255;
				actor.restore_easing_state ();

                ulong handler_id = 0UL;
				handler_id = actor.transition_stopped.connect (() => {
                    actor.disconnect (handler_id);
                    actor.opacity = 255;
				});
            }
        }

		public void open (uint32 xid)
		{
			if (!ready)
				return;

			if (visible) {
				close ();
				return;
			}


			workspaces = new List<Workspace> ();

            foreach (var workspace in screen.get_workspaces ())
                workspaces.append (workspace);


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

                    var actor = window.get_compositor_private () as WindowActor;
                    if (actor != null) {
                        actor.hide ();
                    } 
                }
			}

            target_window = find_window_by_xid (xid);
			if (target_window == null) {
                cleanup ();
				return;
            }

            //(wm as WindowManagerGala).toggle_background_blur (true);
			grab_key_focus ();

			//modal_proxy = wm.push_modal ();
			//modal_proxy.keybinding_filter = keybinding_filter;

            update_previewer ();

			visible = true;
			ready = true;

            target_window = null;
            change_preview (xid);
		}

        public void update_previewer ()
        {
            int n = target_window.get_monitor();
            var geometry = screen.get_monitor_geometry (n);

            set_position (geometry.x, geometry.y);
            set_size (geometry.width, geometry.height);
        }

		bool keybinding_filter (KeyBinding binding)
		{
			var name = binding.get_name ();
			return (name != "expose-windows" && name != "expose-all-windows");
		}

		public void close ()
		{
			if (!visible || !ready)
				return;

            //(wm as WindowManagerGala).toggle_background_blur (false);

			ready = false;

            if (target_window != null)
                (target_window.get_compositor_private () as WindowActor).hide ();
            target_window = null;

			//wm.pop_modal (modal_proxy);

			Clutter.Threads.Timeout.add (10, () => {
				cleanup ();

				return false;
			});
		}

		void cleanup ()
		{
			ready = true;
			visible = false;

            foreach (var window in screen.get_active_workspace ().list_windows ())
				if (window.showing_on_its_workspace ())
					((Actor) window.get_compositor_private ()).show ();

			destroy_all_children ();
		}
	}
}

