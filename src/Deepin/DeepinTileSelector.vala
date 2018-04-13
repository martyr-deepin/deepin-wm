//
//  Copyright (C) 2018 Deepin Technology Co., Ltd.
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
	public class DeepinTileSelector : Actor, ActivatableComponent
	{
		const int BORDER = 10;
		const int TOP_GAP = 10;
		const int BOTTOM_GAP = 10;

		public WindowManager wm { get; construct; }
        public WindowActor? tile_target {get ;set; }
        public signal bool closed ();

        TileSide target_side = TileSide.LEFT;
        Workspace? target_workspace = null;

		Meta.Screen screen;

		ModalProxy modal_proxy;
		bool ready;
        DeepinWindowFlowContainer? container = null;

		public DeepinTileSelector (WindowManager wm)
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

		~DeepinTileSelector ()
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
		 */
		public void open (HashTable<string, Variant>? hints = null)
		{
			if (!ready)
				return;

			if (visible) {
				close ();
				return;
			}

            //TODO: what if tile_target is not the active workspace and the same monitor
            if (tile_target == null)
                return;

            var target_window = (tile_target as WindowActor).get_meta_window ();
            var target_rect = target_window.get_frame_rect ();

			var used_windows = new SList<Window> ();
            foreach (var window in screen.get_active_workspace ().list_windows ()) {
                var actor = window.get_compositor_private () as WindowActor;

                if (window.window_type != WindowType.NORMAL &&
                    window.window_type != WindowType.DOCK) {
                    if (actor != null) {
                        actor.hide ();
                    }
                    continue;
                }

                if (actor == tile_target)
                    continue;

                if (window.window_type == WindowType.DOCK || window.is_on_all_workspaces ())
                    continue;

                if (!window.can_tile_side_by_side () ||
                        window.is_shaded () ||
                        window.is_fullscreen () ||
                        window.get_maximized () == Meta.MaximizeFlags.BOTH ||
                        window.get_monitor () != target_window.get_monitor ()) {
                    if (actor != null) {
                        actor.hide ();
                    }
                    continue;
                }

                used_windows.append (window);
            }

			var n_windows = used_windows.length ();
			if (n_windows == 0) {
                cleanup ();
				return;
            }

			ready = false;

			modal_proxy = wm.push_modal ();
            if (!modal_proxy.grabbed) {
                cleanup ();
            }
			modal_proxy.keybinding_filter = keybinding_filter;

			grab_key_focus ();

            (wm as WindowManagerGala).toggle_background_blur (true);

            target_workspace = screen.get_active_workspace ();
            target_workspace.window_removed.connect (remove_window);

            var geometry = target_window.get_work_area_current_monitor ();

            target_side = target_window.get_tile_mode ();
            assert (target_side == TileSide.LEFT || target_side == TileSide.RIGHT);

            container = new DeepinWindowFlowContainer (target_workspace);
            container.padding_top = TOP_GAP;
            container.padding_left = container.padding_right = BORDER;
            container.padding_bottom = BOTTOM_GAP;
            container.set_size (geometry.width / 2, geometry.height);

            container.window_activated.connect (thumb_activated);
            container.window_entered.connect (on_window_entered);
            add_child (container);

            if (target_side == TileSide.LEFT) {
                this.set_position (geometry.x + geometry.width / 2, geometry.y);
            } else {
                this.set_position (geometry.x, geometry.y);
            }
            this.set_size (geometry.width / 2, geometry.height);

			foreach (var window in used_windows) {
				unowned WindowActor actor = window.get_compositor_private () as WindowActor;
				if (actor != null)
					actor.hide ();

				container.add_window (window);
			}

			visible = true;
            container.open ();
			ready = true;
		}

		bool keybinding_filter (KeyBinding binding)
		{
            return false;
			var name = binding.get_name ();
			return (name != "expose-windows" && name != "expose-all-windows");
		}

		void restack_windows (Screen screen)
		{
			foreach (var child in get_children ())
				((DeepinWindowFlowContainer) child).restack_windows (screen);
		}

		void remove_window (Window window)
		{
			if (container == null)
				return;

			container.remove_window (window);
            if (container.get_n_children () == 0) {
                close ();
            }

		}

        void on_window_entered (Window window)
        {
			if (container == null) return;
            container.select_window (window, true);
        }

        void activate_selected_window ()
        {
            if (container == null || !container.has_selected_window ())
                return;

            thumb_activated (container.get_selected_clone ().window);
        }

		void select_window_by_order (bool backward)
		{
			container.select_window_by_order (backward);
		}

		void thumb_activated (Window window)
		{
			if (window.get_workspace () == target_workspace) {
				close ();

				window.activate (screen.get_display ().get_current_time_roundtrip ());
                window.tile_by_side (target_side == TileSide.LEFT ? TileSide.RIGHT : TileSide.LEFT);
			} 
		}

		/**
		 * {@inheritDoc}
		 */
		public void close ()
		{
			if (!visible || !ready)
				return;

            (wm as WindowManagerGala).toggle_background_blur (false);

            target_workspace.window_removed.disconnect (remove_window);

			ready = false;

			wm.pop_modal (modal_proxy);

            container.close ();

			Clutter.Threads.Timeout.add (100, () => {
				cleanup ();

				return false;
			});

            closed ();
		}

		void cleanup ()
		{
			ready = true;
			visible = false;

			container.destroy ();
            container = null;

            foreach (var window in screen.get_active_workspace ().list_windows ())
				if (window.showing_on_its_workspace ())
					((Actor) window.get_compositor_private ()).show ();
		}
	}
}

