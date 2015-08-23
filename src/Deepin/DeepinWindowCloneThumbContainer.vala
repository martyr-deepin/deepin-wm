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
	/**
	 * Container which controls the layout of a set of WindowClones. The WindowClones will be placed
	 * in their real position.
	 */
	public class DeepinWindowCloneThumbContainer : Actor
	{
		const int WINDOW_FADE_DURATION = 200;
		const AnimationMode WINDOW_FADE_MODE = AnimationMode.EASE_IN_OUT_CUBIC;
		const int WINDOW_OPACITY_SELECTED = 255;
		const int WINDOW_OPACITY_UNSELECTED = 100;

		public signal void window_added (Window window);
		public signal void window_activated (Window window);
		public signal void window_closing (Window window);
		public signal void window_dragging (Window window);
		public signal void window_removed (Window window);

		public Workspace workspace { get; construct; }

		public int padding_top { get; set; default = 12; }
		public int padding_left { get; set; default = 12; }
		public int padding_right { get; set; default = 12; }
		public int padding_bottom { get; set; default = 12; }

		public DeepinWindowCloneThumbContainer (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		/**
		 * Create a DeepinWindowClone for a MetaWindow and add it to the group
		 *
		 * @param window The window for which to create the DeepinWindowClone for
		 */
		public void add_window (Window window)
		{
			unowned Meta.Display display = window.get_display ();
			var children = get_children ();

			GLib.SList<unowned Meta.Window> windows = new GLib.SList<unowned Meta.Window> ();
			foreach (unowned Actor child in children) {
				unowned DeepinWindowClone window_clone = (DeepinWindowClone)child;
				windows.prepend (window_clone.window);
			}
			windows.prepend (window);
			windows.reverse ();

			var windows_ordered = display.sort_windows_by_stacking (windows);

			// TODO: thumbnail mode
			// enable thumbnail mode for window clone to hide shadow and icon
			var new_window = new DeepinWindowClone (window, true);

			new_window.activated.connect (on_window_activated);
			new_window.closing.connect (on_window_closing);
			new_window.destroy.connect (on_window_destroyed);
			new_window.request_reposition.connect (relayout);
			new_window.notify["dragging"].connect (() => {
				if (new_window.dragging) {
					window_dragging (new_window.window);
				}
			});

			var added = false;
			unowned Meta.Window? target = null;
			foreach (unowned Meta.Window w in windows_ordered) {
				if (w != window) {
					target = w;
					continue;
				}
				break;
			}

			foreach (unowned Actor child in children) {
				unowned DeepinWindowClone window_clone = (DeepinWindowClone)child;
				if (target == window_clone.window) {
					insert_child_above (new_window, window_clone);
					added = true;
					break;
				}
			}

			// top most or no other children
			if (!added) {
				// TODO: add window animation
				add_child (new_window);
				window_added (window);

				new_window.save_easing_state ();

				new_window.set_easing_duration (WINDOW_FADE_DURATION);
				new_window.set_easing_mode (WINDOW_FADE_MODE);
				new_window.opacity = WINDOW_OPACITY_UNSELECTED;

				new_window.restore_easing_state ();
			}

			relayout ();
		}

		/**
		 * Find and remove the DeepinWindowClone for a MetaWindow.
		 */
		public void remove_window (Window window)
		{
			foreach (var child in get_children ()) {
				if (((DeepinWindowClone)child).window == window) {
					remove_child (child);
					window_removed (window);
					break;
				}
			}
			relayout ();
		}

		void on_window_activated (DeepinWindowClone clone)
		{
			window_activated (clone.window);
		}

		void on_window_closing (DeepinWindowClone clone)
		{
			window_closing (clone.window);
		}

		void on_window_destroyed (Actor actor)
		{
			var window = actor as DeepinWindowClone;
			if (window == null) {
				return;
			}

			window.destroy.disconnect (on_window_destroyed);
			window.activated.disconnect (on_window_activated);
			window.closing.disconnect (on_window_closing);
			window.request_reposition.disconnect (relayout);

			Idle.add (() => {
				relayout ();
				return false;
			});
		}

		/**
		 * Another window clone with same Meta.Window is closing, sync closing animation with it.
		 */
		public void sync_closing_animation (Window window)
		{
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					(child as DeepinWindowClone).start_closing_animation ();
					break;
				}
			}
		}

		/**
		 * Select target window by increasing its z-order to top.
		 */
		public void select_window (Window window)
		{
			foreach (var child in get_children ()) {
				child.save_easing_state ();

				child.set_easing_duration (WINDOW_FADE_DURATION);
				child.set_easing_mode (WINDOW_FADE_MODE);

				if (((DeepinWindowClone)child).window == window) {
					set_child_at_index (child, -1);
					child.opacity = WINDOW_OPACITY_SELECTED;
				} else {
					child.opacity = WINDOW_OPACITY_UNSELECTED;
				}

				child.restore_easing_state ();
			}
		}

		/**
		 * Recalculate the positions of the windows and animate them to the resulting spots.
		 */
		public void relayout ()
		{
			float thumb_width, thumb_height;
			DeepinWorkspaceThumbCloneContainer.get_thumb_size (
				workspace.get_screen (), out thumb_width, out thumb_height);

			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
			float scale = thumb_width != 0 ? thumb_width / (float)monitor_geom.width : 0.5f;

			foreach (var child in get_children ()) {
				unowned DeepinWindowClone window_clone = (DeepinWindowClone)child;
				Meta.Rectangle rect;
#if HAS_MUTTER312
				rect = window_clone.window.get_frame_rect ();
#else
				rect = window_clone.window.get_outer_rect ();
#endif
				DeepinUtils.scale_rectangle (ref rect, scale);
				window_clone.take_slot (rect);
			}
		}
	}
}
