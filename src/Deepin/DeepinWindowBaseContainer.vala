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
	/**
	 * Base container to controls the layout of a set of window clones.
	 */
	public abstract class DeepinWindowBaseContainer : Actor
	{
		public signal void window_added (Window window);
		public signal void window_activated (Window window);
		public signal void window_closing (Window window);
		public signal void window_dragging (Window window);
		public signal void window_removed (Window window);
		public signal void window_selected (Window window);
		public signal void window_entered (Window window);

		public Workspace workspace { get; construct; }

		public const int LAYOUT_DURATION = 400;

		public int layout_duration { get; set; default = LAYOUT_DURATION; }

		/**
		 * The window that is currently selected via keyboard shortcuts. It is not necessarily the
		 * same as the active window.
		 */
		internal Window? selected_window = null;

		/**
		 * Mark if multitasking view opend.
		 */
		internal bool opened = false;

		/**
		 * Recalculate the positions of the windows and animate them to the resulting spots.
		 *
		 * @param selecting Check if is action that window clone is selecting.
		 */
		public abstract void relayout (bool selecting = false, bool animated = true);

		/**
		 * Get position rectangle for target window.
		 */
		public abstract ActorBox get_layout_box_for_window (DeepinWindowClone window_clone);

		/**
		 * Change current selected window and call relayout to adjust the size.
		 */
		public abstract void do_select_clone (DeepinWindowClone window_clone, bool select,
											  bool animate = true);

		DeepinWindowBaseContainer (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			actor_added.connect (on_actor_added);
		}

		~DeepinWindowBaseContainer ()
		{
			actor_added.disconnect (on_actor_added);
		}

		public virtual void on_actor_added (Actor new_actor)
		{
			// setup animation for new window
			var new_window = new_actor as DeepinWindowClone;
			var box = get_layout_box_for_window (new_window);
			var rect = DeepinUtils.new_rect_for_actor_box (box);
			new_window.take_slot (rect, false);

			new_window.set_scale (0, 0);
			new_window.start_fade_in_animation ();
		}

		/**
		 * Check if exists a selected window.
		 */
		public bool has_selected_window ()
		{
			return get_selected_clone () != null;
		}

		/**
		 * Check if related child DeepinWindowClone exsits for a MetaWindow.
		 *
		 * @param window The window to searching for
		 */
		public bool contains_window (Window window)
		{
			return get_clone_for_window (window) != null;
		}

		/**
		 * Get current selected window clone if exists.
		 */
		public DeepinWindowClone? get_selected_clone ()
		{
			return get_clone_for_window (selected_window);
		}

		/**
		 * Get related window clone for MetaWindow.
		 */
		public DeepinWindowClone? get_clone_for_window (Window? window)
		{
			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == window) {
					return child as DeepinWindowClone;
				}
			}
			return null;
		}

		/**
		 * Select related window clone for MetaWindow.
		 */
		public void select_window (Window window, bool need_relayout = true)
		{
			select_clone (get_clone_for_window (window), need_relayout);
		}

		/**
		 * Selecte target window clone.
		 */
		public void select_clone (DeepinWindowClone? window_clone, bool need_relayout = true)
		{
			restack_windows (workspace.get_screen ());

			foreach (var child in get_children ()) {
				var child_clone = child as DeepinWindowClone;
				if (child_clone == window_clone) {
					do_select_clone (child_clone, true);
					selected_window = child_clone.window;
					window_selected (selected_window);
				} else {
					do_select_clone (child_clone, false);
				}
			}

			if (need_relayout) {
				relayout (true);
			}
		}

		/**
		 * Create a DeepinWindowClone for a MetaWindow and add it to the group.
		 *
		 * @param window The window for which to add the DeepinWindowClone for
		 */
		public virtual DeepinWindowClone? add_window (Window window, bool thumbnail_mode = false)
		{
			if (contains_window (window)) {
				return null;
			}

			var display = window.get_display ();
			var children = get_children ();

			var windows = new GLib.SList<Meta.Window> ();
			foreach (var child in children) {
				var window_clone = child as DeepinWindowClone;
				windows.prepend (window_clone.window);
			}
			windows.prepend (window);
			windows.reverse ();

			var windows_ordered = display.sort_windows_by_stacking (windows);

			var new_window = new DeepinWindowClone (window, thumbnail_mode);
            new_window.layout_duration = layout_duration;

			new_window.activated.connect (on_window_activated);
			new_window.closing.connect (on_window_closing);
			new_window.destroy.connect (on_window_destroyed);
			new_window.entered.connect (on_window_entered);
			new_window.request_reposition.connect (on_request_reposition);
			new_window.notify["dragging"].connect (() => {
				if (new_window.dragging) {
					window_dragging (new_window.window);
				}
			});

			int index = windows_ordered.index (window);
			insert_child_at_index (new_window, index);
			window_added (window);

			if (selected_window == window) {
				do_select_clone (new_window, true, false);
			} else {
				do_select_clone (new_window, false, false);
			}

			relayout ();

			return new_window;
		}

		/**
		 * Find and remove the related DeepinWindowClone for a MetaWindow.
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

		void on_window_activated (DeepinWindowClone window_clone)
		{
			window_activated (window_clone.window);
		}

		void on_window_entered (DeepinWindowClone window_clone)
		{
			window_entered (window_clone.window);
		}

		void on_window_closing (DeepinWindowClone window_clone)
		{
			window_closing (window_clone.window);
		}

		void on_request_reposition (DeepinWindowClone window_clone)
		{
			relayout ();
		}

		void on_window_destroyed (Actor actor)
		{
			var window = actor as DeepinWindowClone;
			if (window == null) {
				return;
			}

			window.destroy.disconnect (on_window_destroyed);
			window.activated.disconnect (on_window_activated);
			window.activated.disconnect (on_window_entered);
			window.closing.disconnect (on_window_closing);
			window.request_reposition.disconnect (on_request_reposition);

			Idle.add (() => {
				relayout ();
				return false;
			});
		}

		ulong sync_transitions_completed_id = 0;

		/**
		 * Add child for that the related window container added one.
		 */
		public void sync_add_window (Window window)
		{
			foreach (var child in get_children ()) {
				var window_clone = child as DeepinWindowClone;
				if (window_clone.window == window) {
					// cancel closing animation if exists and start fade-in animation
					if (sync_transitions_completed_id != 0) {
						SignalHandler.disconnect (child, sync_transitions_completed_id);
						sync_transitions_completed_id = 0;
					}
					window_clone.remove_all_transitions ();
					window_clone.start_fade_in_animation ();
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
					(child as DeepinWindowClone).start_fade_out_animation ();
					sync_transitions_completed_id = child.transitions_completed.connect (() => {
						sync_transitions_completed_id = 0;
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
					(child as DeepinWindowClone).start_fade_out_animation ();
					break;
				}
			}
		}

		/**
		 * Sort the windows z-order by their actual stacking to make intersections during animations
		 * correct.
		 */
		public virtual void restack_windows (Screen screen)
		{
			var display = screen.get_display ();
			var children = get_children ();

			var windows = new GLib.SList<Meta.Window> ();
			foreach (var child in children) {
				var window_clone = child as DeepinWindowClone;
				windows.prepend (window_clone.window);
			}

			var windows_ordered = display.sort_windows_by_stacking (windows);

			int i = 0;
			foreach (var window in windows_ordered) {
				foreach (var child in children) {
					if ((child as DeepinWindowClone).window == window) {
						set_child_at_index (child, i);
						children.remove (child);
						break;
					}
				}
				i++;
			}
		}

		/**
		 * Multitasking view opened.
		 */
		public virtual void open (Window? focus_window = null, bool animate = true)
		{
			if (opened) {
				return;
			}

			opened = true;

			restack_windows (workspace.get_screen ());

			selected_window = null;
		}

		/**
		 * Multitasking view closed.
		 */
		public virtual void close ()
		{
			if (!opened) {
				return;
			}

			opened = false;
		}
	}
}
