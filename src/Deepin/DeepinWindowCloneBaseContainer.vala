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
	 * Base container to controls the layout of a set of window clones.
	 */
	public abstract class DeepinWindowCloneBaseContainer : Actor
	{
		public signal void window_added (Window window);
		public signal void window_activated (Window window);
		public signal void window_closing (Window window);
		public signal void window_dragging (Window window);
		public signal void window_removed (Window window);
		public signal void window_selected (Window window);

		public Workspace workspace { get; construct; }

		/**
		 * The window that is currently selected via keyboard shortcuts. It is not necessarily the
		 * same as the active window.
		 */
		internal DeepinWindowClone? current_window;

		/**
		 * Recalculate the positions of the windows and animate them to the resulting spots.
		 */
		public abstract void relayout ();

		/**
		 * Change current selected window and call relayout to adjust the size.
		 */
		public abstract void change_current_window (DeepinWindowClone? window, bool need_relayout = true);

		public DeepinWindowCloneBaseContainer (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		/**
		 * Check if exists a selected window.
		 */
		public bool has_selected_window ()
		{
			return current_window != null && contains (current_window);
		}

		public void select_window (Window window)
		{
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					change_current_window ((child as DeepinWindowClone));
					return;
				}
			}
		}

		/**
		 * Check if releated child DeepinWindowClone exsits for a MetaWindow.
		 *
		 * @param window The window to searching for
		 */
		public bool contains_window (Window window)
		{
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Create a DeepinWindowClone for a MetaWindow and add it to the group.
		 *
		 * @param window The window for which to add the DeepinWindowClone for
		 */
		public virtual void add_window (Window window)
		{
			if (contains_window (window)) {
				return;
			}

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
				add_child (new_window);
				window_added (window);
			}

			// make new window selected default and relayout
			change_current_window (new_window, true);
		}

		/**
		 * Find and remove the releated DeepinWindowClone for a MetaWindow.
		 *
		 * @param window The window for which to remove the DeepinWindowClone for
		 */
		public virtual void remove_window (Window window)
		{
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					remove_child (child);
					window_removed (window);
					break;
				}
			}
			relayout ();
		}

		/* Child DeepinWindowClone signals */

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

		ulong transitions_completed_id = 0;

		/**
		 * Add child for that the related window container added one.
		 */
		public void sync_add_window (Window window)
		{
			// remove signals and transitions if exists
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					if (transitions_completed_id != 0) {
						SignalHandler.disconnect (child, transitions_completed_id);
						transitions_completed_id = 0;
					}
					child.remove_all_transitions ();
					(child as DeepinWindowClone).restore_close_animation ();
					return;
				}
			}

			// add window as normal if not exists
			add_window (window);
		}

		/**
		 * Add child for that the related window container removed one.
		 */
		public void sync_remove_window (Window window)
		{
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					(child as DeepinWindowClone).start_close_animation ();
					transitions_completed_id = child.transitions_completed.connect (() => {
						remove_window (window);
					});
					break;
				}
			}
		}

		/**
		 * Window clone with same MetaWindow in the related container is closing, synchronize
		 * closing animation for it.
		 */
		public void sync_window_close_animation (Window window)
		{
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					(child as DeepinWindowClone).start_close_animation ();
					break;
				}
			}
		}
	}
}
