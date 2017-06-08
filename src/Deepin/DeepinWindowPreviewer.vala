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

        Meta.Window? target_window = null;
        Actor? target_clone = null;
        Workspace? open_workspace = null;
        Actor? dock_actors = null;
        Actor? preview_group = null;
        bool opening = false;
        bool closing = false;

		public WindowPreviewer (WindowManager wm)
		{
			Object (wm : wm);
		}

		construct
		{
			screen = wm.get_screen ();

			screen.workspace_switched.connect (close);
            screen.monitors_changed.connect (update_previewer);

            preview_group = new Actor ();
            add_child (preview_group);

            dock_actors = new Actor ();
            add_child (dock_actors);

            reactive = true;
			visible = false;
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
            foreach (var workspace in screen.get_workspaces ()) {
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
            bool first_selection = target_window == null;

			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.preview_duration;
			if (!animation_settings.enable_animations) {
                duration = 0;
			}

            if (target_window != null && (uint32)target_window.get_xwindow () == xid)
                return;

            if (target_window != null) {
                var clone = target_clone;

                //fade out
                target_window = null;
                target_clone = null;

                if (duration != 0) {
                    clone.opacity = 255;

                    clone.save_easing_state ();
                    clone.set_easing_mode (Clutter.AnimationMode.LINEAR);
                    clone.set_easing_duration (duration);
                    clone.opacity = 0;
                    clone.restore_easing_state ();

                    ulong handler_id = 0UL;
                    handler_id = clone.transition_stopped.connect (() => {
                        clone.disconnect (handler_id);
                        clone.destroy ();
                    });
                } else {
                    clone.hide ();
                    clone.destroy ();
                }
            }

            target_window = find_window_by_xid (xid);
            if (target_window != null) {
                var actor = target_window.get_compositor_private () as WindowActor;
                var clone = new SafeWindowClone (target_window, true);
                target_clone = clone;
                preview_group.add_child (clone);
                clone.x = actor.x;
                clone.y = actor.y;

                if (duration != 0 && 
                        (!first_selection || !target_window.showing_on_its_workspace ())) {
                    clone.opacity = 0;
                    clone.show ();
                    clone.save_easing_state ();
                    clone.set_easing_mode (Clutter.AnimationMode.LINEAR);
                    clone.set_easing_duration (duration);
                    clone.opacity = 255;
                    clone.restore_easing_state ();

                    ulong handler_id = 0UL;
                    handler_id = clone.transition_stopped.connect (() => {
                        clone.disconnect (handler_id);
                        clone.opacity = 255;
                    });
                } 
            }
        }

		void hide_windows (Workspace workspace)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.preview_duration;
			if (!animation_settings.enable_animations) {
                duration = 0;
			}

            foreach (var window in workspace.list_windows ()) {
                if (window.window_type == WindowType.DOCK)
                    continue;

                if (window.is_on_all_workspaces () && window.get_workspace () != workspace)
                    continue;

                var actor = window.get_compositor_private () as WindowActor;
                if (actor != null && actor.visible) {
                    if (duration != 0) {
                        actor.opacity = 255;

                        actor.save_easing_state ();
                        actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_CUBIC);
                        actor.set_easing_duration (duration);
                        actor.opacity = 0;
                        actor.restore_easing_state ();

                        ulong handler_id = 0UL;
                        handler_id = actor.transition_stopped.connect (() => {
                            actor.disconnect (handler_id);
                            actor.hide ();
                            actor.opacity = 255;
                        });
                    } else {
                        actor.hide ();
                    }
                } 
            }
		}

		void restore_windows (Workspace workspace)
		{
			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.preview_duration;
			if (!animation_settings.enable_animations) {
                duration = 0;
			}

			var screen = wm.get_screen ();

            // if ws changed, there is nothing to do
            if (workspace != screen.get_active_workspace ())
                return;

            foreach (var window in workspace.list_windows ()) {
                if (window.showing_on_its_workspace ()) {
                    var actor = window.get_compositor_private () as Actor;
                    actor.remove_all_transitions ();
                    if (window != target_window && !actor.visible && duration != 0) {
                        actor.opacity = 0;
                        actor.show ();

                        actor.save_easing_state ();
                        actor.set_easing_mode (Clutter.AnimationMode.EASE_IN_OUT_CUBIC);
                        actor.set_easing_duration (duration);
                        actor.opacity = 255;
                        actor.restore_easing_state ();

                        ulong handler_id = 0UL;
                        handler_id = actor.transition_stopped.connect (() => {
                                actor.disconnect (handler_id);
                                actor.opacity = 255;
                                });
                    } else {
                        actor.opacity = 255;
                        actor.show ();
                    }
                } 
            }

            var actor = target_window.get_compositor_private () as Actor;
            actor.opacity = 255;
            // target_window could reside in another workspace
            if (target_window.showing_on_its_workspace ()) {
                actor.show ();
            }
		}

		void collect_dock_windows ()
		{
            dock_actors.destroy_all_children ();

			foreach (var actor in Compositor.get_window_actors (screen)) {
				var window = actor.get_meta_window ();
                actor.opacity = 0;

                if (window.wm_class == "dde-dock") {
                    var clone = new SafeWindowClone (window, true);
                    actor.notify["position"].connect(() => {
                        clone.x = actor.x;
                        clone.y = actor.y;
                    });
                    clone.x = actor.x;
                    clone.y = actor.y;
                    dock_actors.add_child (clone);
                }
			}
		}

		public void open (uint32 xid)
		{
			if (visible || opening) {
                warning ("preview already opened\n");
				return;
			}

            if (closing) {
                warning ("preview is closing!\n");
                closing = false;
            }

			grab_key_focus ();
            opening = true;


            Meta.verbose ("preview opened\n");
			visible = true;

			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.preview_duration;
			if (!animation_settings.enable_animations) {
                duration = 0;
			}

            open_workspace = screen.get_active_workspace ();

            hide_windows (open_workspace);
            collect_dock_windows ();
            update_previewer ();

            change_preview (xid);
			if (target_window == null) {
                close ();
				return;
            }

            Timeout.add(duration, () => {
                if (opening) {
                    opening = false;
                }
                return false;
            });
		}

        public void update_previewer ()
        {
            if (visible && target_window != null) {
                int n = target_window.get_monitor();
                var geometry = screen.get_monitor_geometry (n);

                set_position (geometry.x, geometry.y);
                set_size (geometry.width, geometry.height);
            }
        }

		public void close ()
		{
			if (!visible || closing)
				return;

            Meta.verbose ("preview close\n");
			visible = false;

            if (opening) {
                opening = false;
            }

            closing = true;

            preview_group.destroy_all_children ();
            dock_actors.destroy_all_children ();

            restore_windows (open_workspace);

			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			var duration = animation_settings.preview_duration;
			if (!animation_settings.enable_animations) {
                duration = 0;
			}
            Timeout.add(duration, () => {
                closing = false;
                return false;
            });

            target_window = null;
            target_clone = null;
            open_workspace = null;

		}
	}

}

