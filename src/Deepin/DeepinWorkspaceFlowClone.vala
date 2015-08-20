//
//  Copyright (C) 2014 Deepin, Inc.
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
	// TODO: doc
	/**
	 * This is the container which manages a clone of the background which will be scaled and
	 * animated inwards, a DeepinWindowCloneFlowContainer for the windows on this workspace and also
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
		 * A window has been selected, the DeepinMultitaskingView should consider activating and
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
		public DeepinWindowCloneFlowContainer window_container { get; private set; }

		/**
		 * Own the related thumbnail workspace clone so that signals and events could be dispatched
		 * easily.
		 */
		public DeepinWorkspaceThumbClone thumb_workspace { get; private set; }

#if HAS_MUTTER314
		BackgroundManager background;
#else
		Background background;
#endif
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

			background = new DeepinFramedBackground (workspace.get_screen ());
			background.reactive = true;
			background.button_press_event.connect (() => {
				selected (true);
				return false;
			});

			thumb_workspace = new DeepinWorkspaceThumbClone (workspace);
			thumb_workspace.selected.connect (() => {
				if (workspace != screen.get_active_workspace ()) {
					selected (false);
				}
			});

			window_container = new DeepinWindowCloneFlowContainer ();
			window_container.window_activated.connect ((w) => window_activated (w));
			window_container.window_selected.connect (
				(w) => thumb_workspace.window_container.select_window (w));
			window_container.width = monitor_geom.width;
			window_container.height = monitor_geom.height;
			screen.restacked.connect (window_container.restack_windows);

			// sync window closing animation
			thumb_workspace.window_container.window_closing.connect (
				window_container.sync_closing_animation);
			window_container.window_closing.connect (
				thumb_workspace.window_container.sync_closing_animation);

			var thumb_drop_action = new DragDropAction (
				DragDropActionType.DESTINATION, "deepin-multitaskingview-window");
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

			add_child (background);
			add_child (window_container);

			// add existing windows
			var windows = workspace.list_windows ();
			foreach (var window in windows) {
				if (window.window_type == WindowType.NORMAL && !window.on_all_workspaces &&
					window.get_monitor () == screen.get_primary_monitor ()) {
					window_container.add_window (window);
					thumb_workspace.window_container.add_window (window);
				}
			}

			var listener = WindowListener.get_default ();
			listener.window_no_longer_on_all_workspaces.connect (add_window);
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

			background.destroy ();
		}

		/**
		 * Add a window to the DeepinWindowCloneFlowContainer and the DeepinWorkspaceThumbClone if
		 * it really belongs to this workspace and this monitor.
		 */
		void add_window (Window window)
		{
			if (window.window_type != WindowType.NORMAL || window.get_workspace () != workspace ||
				window.on_all_workspaces ||
				window.get_monitor () != window.get_screen ().get_primary_monitor ()) {
				return;
			}

			foreach (var child in window_container.get_children ()) {
				if (((DeepinWindowClone)child).window == window) {
					return;
				}
			}

			thumb_workspace.window_container.add_window (window);
			window_container.add_window (window);

			// start animation after all containers added window
			thumb_workspace.start_window_added_animation ();
		}

		/**
		 * Remove a window from the DeepinWindowCloneFlowContainer and the DeepinWorkspaceThumbClone.
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

		/**
		 * Animates the background to its scale, causes a redraw on the DeepinWorkspaceThumbClone
		 * and makes sure the DeepinWindowCloneFlowContainer animates its windows to their tiled
		 * layout.  Also sets the current_window of the DeepinWindowCloneFlowContainer to the active
		 * window if it belongs to this workspace.
		 */
		public void open ()
		{
			if (opened) {
				return;
			}

			opened = true;

			var screen = workspace.get_screen ();
			var display = screen.get_display ();
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());

			int top_offset =
				(int)(monitor_geom.height * DeepinMultitaskingView.FLOW_CLONE_TOP_OFFSET_PERCENT);
			int bottom_offset =
				(int)(monitor_geom.height * DeepinMultitaskingView.HORIZONTAL_OFFSET_PERCENT);
			float scale =
				(float)(monitor_geom.height - top_offset - bottom_offset) / monitor_geom.height;
			float pivot_y = top_offset / (monitor_geom.height - monitor_geom.height * scale);

			background.set_pivot_point (0.5f, pivot_y);

			background.save_easing_state ();

			background.set_easing_duration (DeepinMultitaskingView.TOGGLE_DURATION);
			background.set_easing_mode (AnimationMode.EASE_OUT_BACK);
			background.set_scale (scale, scale);

			background.restore_easing_state ();

			window_container.padding_top = top_offset;
			window_container.padding_left = window_container.padding_right =
				(int)(monitor_geom.width - monitor_geom.width * scale) / 2;
			window_container.padding_bottom = bottom_offset;

			window_container.open (
				screen.get_active_workspace () == workspace ? display.get_focus_window () : null);
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

			background.save_easing_state ();

			background.set_easing_duration (300);
			background.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
			background.set_scale (1, 1);

			background.restore_easing_state ();

			window_container.close ();
		}
	}
}
