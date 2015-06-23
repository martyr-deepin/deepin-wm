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
	 * Container which controls the layout of a set of
	 * WindowClones. The WindowClones will be placed in their real
	 * position.
	 */
	public class DeepinWindowCloneThumbContainer : Actor
	{
		public Workspace workspace { get; construct; }

		public int padding_top { get; set; default = 12; }
		public int padding_left { get; set; default = 12; }
		public int padding_right { get; set; default = 12; }
		public int padding_bottom { get; set; default = 12; }

		/**
		 * The window that is currently selected via keyboard shortcuts. It is not
		 * necessarily the same as the active window.
		 */
		DeepinWindowClone? current_window;

		public DeepinWindowCloneThumbContainer (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			current_window = null;
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
				unowned DeepinWindowClone tw = (DeepinWindowClone) child;
				windows.prepend (tw.window);
			}
			windows.prepend (window);
			windows.reverse ();

			var windows_ordered = display.sort_windows_by_stacking (windows);

			// TODO: thumbnail mode
			// hide shadow and icon for window clone
			var new_window = new DeepinWindowClone (window, true);

			new_window.destroy.connect (on_window_destroyed);
			new_window.request_reposition.connect (reflow);

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
				unowned DeepinWindowClone tw = (DeepinWindowClone) child;
				if (target == tw.window) {
					insert_child_above (new_window, tw);
					added = true;
					break;
				}
			}

			// top most or no other children
			if (!added) {
				add_child (new_window);
			}

			reflow ();
		}

		/**
		 * Find and remove the DeepinWindowClone for a MetaWindow
		 */
		public void remove_window (Window window)
		{
			foreach (var child in get_children ()) {
				if (((DeepinWindowClone) child).window == window) {
					remove_child (child);
					break;
				}
			}

			reflow ();
		}

		void on_window_destroyed (Actor actor)
		{
			var window = actor as DeepinWindowClone;
			if (window == null) {
				return;
			}

			window.destroy.disconnect (on_window_destroyed);
			window.request_reposition.disconnect (reflow);

			Idle.add (() => {
				reflow ();
				return false;
			});
		}

		/**
		 * Select target window by increasing its z-order to top.
		 */
		public void select_window (Window window)
		{
			foreach (var child in get_children ()) {
				if (((DeepinWindowClone) child).window == window) {
					set_child_at_index (child, -1);
					break;
				}
			}
		}

		// TODO:
		/**
		 * Sort the windows z-order by their actual stacking to make intersections
		 * during animations correct.
		 */
		public void restack_windows (Screen screen)
		{
			unowned Meta.Display display = screen.get_display ();
			var children = get_children ();

			GLib.SList<unowned Meta.Window> windows = new GLib.SList<unowned Meta.Window> ();
			foreach (unowned Actor child in children) {
				unowned DeepinWindowClone tw = (DeepinWindowClone) child;
				windows.prepend (tw.window);
			}

			var windows_ordered = display.sort_windows_by_stacking (windows);
			windows_ordered.reverse ();

			foreach (unowned Meta.Window window in windows_ordered) {
				var i = 0;
				foreach (unowned Actor child in children) {
					if (((DeepinWindowClone) child).window == window) {
						set_child_at_index (child, i);
						children.remove (child);
						i++;
						break;
					}
				}
			}
		}

		/**
		 * Recalculate the positions of the windows and animate them
		 * to the resulting spots.
		 */
		public void reflow ()
		{
			// the scale between workspace's thumbnail size and real size
			float scale = 1.0f;
			unowned Screen screen = workspace.get_screen ();
			var monitor_geometry = screen.get_monitor_geometry (screen.get_primary_monitor ());
			if (monitor_geometry.width != 0) {
				scale = width / (float) monitor_geometry.width;
			}

			var windows = new List<InternalUtils.TilableWindow?> ();
			foreach (var child in get_children ()) {
				unowned DeepinWindowClone window = (DeepinWindowClone) child;
				Meta.Rectangle rect;
#if HAS_MUTTER312
				rect = window.window.get_frame_rect ();
#else
				rect = window.window.window.get_outer_rect ();
#endif
				rect = DeepinUtils.scale_rect (rect, scale);
				window.take_slot (rect);
			}

			// TODO:
			// make sure the windows are always in the same order so the algorithm
			// doesn't give us different slots based on stacking order, which can lead
			// to windows flying around weirdly
			// windows.sort ((a, b) => {
			// 	var seq_a = ((DeepinWindowClone) a.id).window.get_stable_sequence ();
			// 	var seq_b = ((DeepinWindowClone) b.id).window.get_stable_sequence ();
			// 	return (int) (seq_b - seq_a);
			// });
		}

		/**
		 * Emit the selected signal for the current_window.
		 */
		public void activate_selected_window ()
		{
			if (current_window != null) {
				current_window.activated ();
			}
		}
	}
}
