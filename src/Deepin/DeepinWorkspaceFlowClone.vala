//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2014 Tom Beckmann
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
	/**
	 * This is the container which manages a clone of the background which will be scaled and
	 * animated inwards, a DeepinWindowFlowContainer for the windows on this workspace and also
	 * holds the instance for the DeepinWorkspaceThumbClone.  The latter is not added to the
	 * DeepinWorkspaceFlowClone itself though but to a container of the DeepinMultitaskingView.
	 */
	public class DeepinWorkspaceFlowClone : Actor
	{
		/**
		 * The amount of time a window has to be over the DeepinWorkspaceFlowClone while in drag
		 * before we activate the workspace.
		 */
		const int HOVER_ACTIVATE_DELAY = 400;

		/**
		 * A window has been activated, the DeepinMultitaskingView should consider activating it and
		 * closing the view.
		 */
		public signal void window_activated (Window window);

		/**
		 * The background has been selected. Switch to that workspace.
		 *
		 * @param close_view If the DeepinMultitaskingView should also consider closing itself after
		 *                   switching.
		 */
		public signal void selected (bool close_view);

		public Workspace workspace { get; construct; }
		public DeepinWindowFlowContainer window_container { get; private set; }

		/**
		 * Own the related thumbnail workspace clone so that signals and events could be dispatched
		 * easily.
		 */
		public DeepinWorkspaceThumbClone thumb_workspace { get; private set; }

		Actor thumb_shape;
		DeepinFramedBackground background;
		float background_scale;
		bool opened;

		uint hover_activate_timeout = 0;

		public DeepinWorkspaceFlowClone (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			opened = false;

			var screen = workspace.get_screen ();
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

            background = new DeepinFramedBackground (screen, workspace.index (), true, false, 1.0f, 28, 6, 40, 6);
            background.reactive = true;
            background.button_press_event.connect (() => {
                selected (true);
                return false;
            });
            background.set_rounded_radius (10);

			thumb_workspace = new DeepinWorkspaceThumbClone (workspace);
            thumb_workspace.set_pivot_point (0.5f, 0.5f);
			thumb_workspace.selected.connect (() => {
				if (workspace != screen.get_active_workspace ()) {
					selected (false);
				}
			});

			window_container = new DeepinWindowFlowContainer (workspace);
			window_container.window_activated.connect ((w) => window_activated (w));
			window_container.window_selected.connect (
				(w) => thumb_workspace.window_container.select_window (w, false));
			window_container.width = monitor_geom.width;
			window_container.height = monitor_geom.height;
			screen.restacked.connect (window_container.restack_windows);

			// sync window closing animation
			thumb_workspace.window_container.window_closing.connect (
				window_container.sync_window_close_animation);
			window_container.window_closing.connect (
				thumb_workspace.window_container.sync_window_close_animation);

			// sync windows in two containers
			thumb_workspace.window_container.actor_added.connect ((a) =>
				window_container.sync_add_window ((a as DeepinWindowClone).window));
			thumb_workspace.window_container.actor_removed.connect ((a) =>
				window_container.sync_remove_window ((a as DeepinWindowClone).window));
			window_container.actor_added.connect ((a) =>
				thumb_workspace.window_container.sync_add_window ((a as DeepinWindowClone).window));
			window_container.actor_removed.connect ((a) =>
				thumb_workspace.window_container.sync_remove_window ((a as DeepinWindowClone).window));

			var thumb_drop_action = new DragDropAction (
				DragDropActionType.DESTINATION, "deepin-multitaskingview-window");
            thumb_drop_action.crossed.connect ((hovered) => {
                var scale = GLib.Value (typeof (float));

                if (hovered) {
                    scale.set_float (1.05f);
                } else {
                    scale.set_float (1.0f);
                }

                thumb_workspace.remove_transition ("deepin-thumb-workspace-hover");
                DeepinUtils.start_animation_group (thumb_workspace, "deepin-thumb-workspace-hover",
                        200,
                        (timeline) => {
                            timeline.set_progress_mode (AnimationMode.EASE_IN_OUT_CUBIC);
                        }, "scale-x", scale, "scale-y", &scale);
            });
			thumb_workspace.add_action (thumb_drop_action);

			var background_drop_action = new DragDropAction (
				DragDropActionType.DESTINATION, "deepin-multitaskingview-window");
			background.add_action (background_drop_action);
			background_drop_action.crossed.connect ((hovered) => {
				if (!hovered && hover_activate_timeout != 0) {
					Source.remove (hover_activate_timeout);
					hover_activate_timeout = 0;
					return;
				}

				if (hovered && hover_activate_timeout == 0) {
					hover_activate_timeout = Timeout.add (HOVER_ACTIVATE_DELAY, () => {
						selected (false);
						hover_activate_timeout = 0;
						return false;
					});
				}
			});

			screen.window_entered_monitor.connect (window_entered_monitor);
			screen.window_left_monitor.connect (window_left_monitor);
			workspace.window_added.connect (add_window);
			workspace.window_removed.connect (remove_window);

            thumb_shape =
                new DeepinCssStaticActor ("deepin-workspace-clone", Gtk.StateFlags.NORMAL);

			add_child (background);
            add_child (thumb_shape);
			add_child (window_container);

			// add existing windows
			var windows = workspace.list_windows ();
			foreach (var window in windows) {
				if (window.window_type == WindowType.NORMAL && !window.on_all_workspaces) {
					window_container.add_window (window);
					thumb_workspace.window_container.add_window (window);
				}
			}

			var listener = WindowListener.get_default ();
			listener.window_no_longer_on_all_workspaces.connect (add_window);

			relayout ();
			screen.monitors_changed.connect (relayout);
		}

		~DeepinWorkspaceFlowClone ()
		{
			var screen = workspace.get_screen ();

			screen.restacked.disconnect (window_container.restack_windows);

			screen.window_entered_monitor.disconnect (window_entered_monitor);
			screen.window_left_monitor.disconnect (window_left_monitor);
			workspace.window_added.disconnect (add_window);
			workspace.window_removed.disconnect (remove_window);

			var listener = WindowListener.get_default ();
			listener.window_no_longer_on_all_workspaces.disconnect (add_window);

			screen.monitors_changed.disconnect (relayout);

			background.destroy ();
		}

		/**
		 * Add a window to the DeepinWindowFlowContainer and the DeepinWorkspaceThumbClone if
		 * it really belongs to this workspace and this monitor.
		 */
		void add_window (Window window)
		{
			if (window.window_type != WindowType.NORMAL || window.get_workspace () != workspace ||
				window.on_all_workspaces) {
				return;
			}

			foreach (var child in window_container.get_children ()) {
				if (((DeepinWindowClone)child).window == window) {
					return;
				}
			}

			thumb_workspace.window_container.add_window (window);
			window_container.add_window (window);
		}

		/**
		 * Remove a window from DeepinWindowFlowContainer and DeepinWorkspaceThumbClone.
		 */
		void remove_window (Window window)
		{
			window_container.remove_window (window);
			thumb_workspace.window_container.remove_window (window);
		}

		void window_entered_monitor (Screen screen, int monitor, Window window)
		{
			add_window (window);
		}

		void window_left_monitor (Screen screen, int monitor, Window window)
		{
			if (monitor == screen.get_primary_monitor ()) {
				remove_window (window);
			}
		}

		void relayout ()
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());

			int top_offset =
				(int)(monitor_geom.height * DeepinMultitaskingView.FLOW_WORKSPACE_TOP_OFFSET_PERCENT);
			int bottom_offset =
				(int)(monitor_geom.height * DeepinMultitaskingView.HORIZONTAL_OFFSET_PERCENT);
            float scale = (1.0f - DeepinMultitaskingView.HORIZONTAL_OFFSET_PERCENT -
                    DeepinMultitaskingView.FLOW_WORKSPACE_TOP_OFFSET_PERCENT);
			float pivot_y =  DeepinMultitaskingView.FLOW_WORKSPACE_TOP_OFFSET_PERCENT / (1.0f - scale);
			background_scale = scale;
			background.set_pivot_point (0.5f, pivot_y);

            thumb_shape.set_size (monitor_geom.width, monitor_geom.height);
			thumb_shape.set_pivot_point (0.5f, pivot_y);

			window_container.width = monitor_geom.width;
			window_container.height = monitor_geom.height;
			window_container.padding_top = top_offset;
			window_container.padding_left = window_container.padding_right =
				(int)(monitor_geom.width - monitor_geom.width * scale) / 2;
			window_container.padding_bottom = bottom_offset;

            //thumb_shape.set_position (top_offset, window_container.padding_left);
		}

		/**
		 * Animates the background to its scale, causes a redraw on the DeepinWorkspaceThumbClone
		 * and makes sure the DeepinWindowFlowContainer animates its windows to their tiled
		 * layout.  Also sets the current_window of the DeepinWindowFlowContainer to the active
		 * window if it belongs to this workspace.
		 */
		public void open (bool animate = true)
		{
			if (opened) {
				return;
			}

			opened = true;

			if (animate) {
				scale_in (true);
			}

			var screen = workspace.get_screen ();
			var display = screen.get_display ();
			var focus_window = screen.get_active_workspace () == workspace ?
				display.get_focus_window () : null;
			window_container.open (focus_window);
			thumb_workspace.window_container.open (focus_window);

            unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
            Timeout.add (animation_settings.multitasking_toggle_duration,
                () => {
                    window_container.window_entered.connect (on_window_entered);
                    return false;
                });
		}

		/**
		 * Close the view again by animating the background back to its scale and the windows back
		 * to their old locations.
		 */
		public void close ()
		{
			if (!opened) {
				return;
			}

			opened = false;

            window_container.window_entered.disconnect (on_window_entered);

			scale_out (true);

			window_container.close ();
			thumb_workspace.window_container.close ();
		}

        void on_window_entered (Meta.Window w)
        {
            if (opened) window_container.select_window (w, true);
        }

		public void scale_in (bool animate)
		{
            unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			if (animate) {
				var scale_value = GLib.Value (typeof (float));
				scale_value.set_float (background_scale);
				DeepinUtils.start_animation_group (background, "open",
                                                   animation_settings.multitasking_toggle_duration,
												   DeepinUtils.clutter_set_mode_ease_out_quint,
												   "scale-x", &scale_value,
												   "scale-y", &scale_value);
				DeepinUtils.start_animation_group (thumb_shape, "open",
                                                   animation_settings.multitasking_toggle_duration,
												   DeepinUtils.clutter_set_mode_ease_out_quint,
												   "scale-x", &scale_value,
												   "scale-y", &scale_value);
			} else {
				background.set_scale (background_scale, background_scale);
                thumb_shape.set_scale (background_scale, background_scale);
			}
		}

		public void scale_out (bool animate)
		{
            unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			if (animate) {
                var screen = workspace.get_screen ();
                var active_index = screen.get_active_workspace ().index ();
                var index = workspace.index ();

				var scale_value = GLib.Value (typeof (float));
				scale_value.set_float (1.0f);

                float orig_x = background.x;
				var x_value = GLib.Value (typeof (float));
				float offset = background.width * (DeepinMultitaskingView.FLOW_WORKSPACE_DISTANCE_PERCENT * 2);
                x_value.set_float (orig_x + (index - active_index) * offset);

                var duration = screen.get_active_workspace () == workspace ?
                    animation_settings.multitasking_toggle_duration : 
                    animation_settings.multitasking_toggle_duration * 7 / 10; 

				var ag = DeepinUtils.start_animation_group (background, "close", 
                                                   duration,
												   DeepinUtils.clutter_set_mode_ease_out_quint,
												   "scale-x", &scale_value, "scale-y", &scale_value,
                                                   "x", &x_value);
                ag.stopped.connect ((is_finished) => {
                    background.x = orig_x;
                });

				ag = DeepinUtils.start_animation_group (thumb_shape, "close", 
                                                   duration,
												   DeepinUtils.clutter_set_mode_ease_out_quint,
												   "scale-x", &scale_value, "scale-y", &scale_value,
                                                   "x", &x_value);
                ag.stopped.connect ((is_finished) => {
                    thumb_shape.x = orig_x;
                });

			} else {
				background.set_scale (1.0f, 1.0f);
                thumb_shape.set_scale (1.0f, 1.0f);
			}
		}
	}
}
