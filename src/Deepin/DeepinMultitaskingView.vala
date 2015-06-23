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
	/**
	 * The central class for the DeepinMultitaskingView which takes care of
	 * preparing the wm, opening the components and holds containers for
	 * the icon groups, the WorkspaceClones and the MonitorClones.
	 */
	public class DeepinMultitaskingView : Actor, ActivatableComponent
	{
		public const int ANIMATION_DURATION = 250;
		public const AnimationMode ANIMATION_MODE = AnimationMode.EASE_OUT_QUAD;
		public const AnimationMode WORKSPACE_ANIMATION_MODE = AnimationMode.EASE_OUT_QUAD;
		const int SMOOTH_SCROLL_DELAY = 500;

		public WindowManager wm { get; construct; }

		Meta.Screen screen;
		ModalProxy modal_proxy;
		bool opened = false;
		bool animating = false;

		bool is_smooth_scrolling = false;

		Actor dock_clones;

		List<MonitorClone> window_containers_monitors;

		Actor flow_workspaces;
		DeepinWorkspaceThumbCloneContainer thumb_workspaces;

		public DeepinMultitaskingView (WindowManager wm)
		{
			Object (wm: wm);
		}

		construct
		{
			visible = false;
			reactive = true;
			clip_to_allocation = true;

			opened = false;
			screen = wm.get_screen ();

			flow_workspaces = new Actor ();
			flow_workspaces.set_easing_mode (WORKSPACE_ANIMATION_MODE);

			thumb_workspaces = new DeepinWorkspaceThumbCloneContainer (screen);
			thumb_workspaces.request_reposition.connect (() => reposition_thumb_workspaces (true));

			dock_clones = new Actor ();

			add_child (thumb_workspaces);
			add_child (flow_workspaces);
			add_child (dock_clones);

			foreach (var workspace in screen.get_workspaces ()) {
				add_workspace (workspace.index ());
			}

			screen.workspace_added.connect (add_workspace);
			screen.workspace_removed.connect (remove_workspace);
			screen.workspace_switched.connect_after ((from, to, direction) => {
				update_positions (opened);
			});

			window_containers_monitors = new List<MonitorClone> ();
			update_monitors ();
			screen.monitors_changed.connect (update_monitors);

			Prefs.add_listener ((pref) => {
				if (pref == Preference.WORKSPACES_ONLY_ON_PRIMARY) {
					update_monitors ();
					return;
				}

				if (Prefs.get_dynamic_workspaces () ||
					(pref != Preference.DYNAMIC_WORKSPACES && pref != Preference.NUM_WORKSPACES)) {
					return;
				}

				Idle.add (() => {
					unowned List<Workspace> existing_workspaces = screen.get_workspaces ();

					foreach (var child in flow_workspaces.get_children ()) {
						unowned DeepinWorkspaceFlowClone workspace_clone = (DeepinWorkspaceFlowClone) child;
						if (existing_workspaces.index (workspace_clone.workspace) < 0) {
							workspace_clone.window_activated.disconnect (activate_window);
							workspace_clone.selected.disconnect (activate_workspace);

							thumb_workspaces.remove_thumb (workspace_clone.related_thumb_workspace);

							workspace_clone.destroy ();
						}
					}

					update_monitors ();
					update_positions (false);

					return false;
				});
			});
		}

		/**
		 * Places the primary container for the WorkspaceClones and the
		 * MonitorClones at the right positions
		 */
		void update_monitors ()
		{
			foreach (var monitor_clone in window_containers_monitors) {
				monitor_clone.destroy ();
			}

			var primary = screen.get_primary_monitor ();

			if (InternalUtils.workspaces_only_on_primary ()) {
				for (var monitor = 0; monitor < screen.get_n_monitors (); monitor++) {
					if (monitor == primary) {
						continue;
					}

					var monitor_clone = new MonitorClone (screen, monitor);
					// TODO: monitors
					monitor_clone.window_selected.connect (activate_window);
					monitor_clone.visible = opened;

					window_containers_monitors.append (monitor_clone);
					wm.ui_group.add_child (monitor_clone);
				}
			}

			var primary_geometry = screen.get_monitor_geometry (primary);

			set_position (primary_geometry.x, primary_geometry.y);
			set_size (primary_geometry.width, primary_geometry.height);
		}

		/**
		 * We generally assume that when the key-focus-out signal is emitted
		 * a different component was opened, so we close in that case.
		 */
		public override void key_focus_out ()
		{
			if (opened && !contains (get_stage ().key_focus)) {
				toggle ();
			}
		}

		/**
		 * Scroll through flow_workspaces
		 */
		public override bool scroll_event (ScrollEvent scroll_event)
		{
			if (scroll_event.direction != ScrollDirection.SMOOTH) {
				return false;
			}

			double dx, dy;
			var event = (Event*)(&scroll_event);
			event->get_scroll_delta (out dx, out dy);

			var direction = MotionDirection.LEFT;

			// concept from maya to detect mouse wheel and proper smooth scroll and prevent
			// too much repetition on the events
			if (Math.fabs (dy) == 1.0) {
				// mouse wheel scroll
				direction = dy > 0 ? MotionDirection.RIGHT : MotionDirection.LEFT;
			} else if (!is_smooth_scrolling) {
				// actual smooth scroll
				var choice = Math.fabs (dx) > Math.fabs (dy) ? dx : dy;

				if (choice > 0.3) {
					direction = MotionDirection.RIGHT;
				} else if (choice < -0.3) {
					direction = MotionDirection.LEFT;
				} else {
					return false;
				}

				is_smooth_scrolling = true;
				Timeout.add (SMOOTH_SCROLL_DELAY, () => {
					is_smooth_scrolling = false;
					return false;
				});
			} else {
				// smooth scroll delay still active
				return false;
			}

			var active_workspace = screen.get_active_workspace ();
			var new_workspace = active_workspace.get_neighbor (direction);

			if (active_workspace != new_workspace) {
				new_workspace.activate (screen.get_display ().get_current_time ());
			}

			return false;
		}

		/**
		 * Places the WorkspaceClones, moves the view so that the active one is shown
		 * and does the same for the IconGroups.
		 *
		 * @param animate Whether to animate the movement or have all elements take their
		 *                positions immediately.
		 */
		void update_positions (bool animate)
		{
			var active_index = screen.get_active_workspace ().index ();
			var active_x = 0.0f;

			foreach (var child in flow_workspaces.get_children ()) {
				unowned DeepinWorkspaceFlowClone workspace_clone = (DeepinWorkspaceFlowClone) child;
				var index = workspace_clone.workspace.index ();
				// TODO: layout
				// var dest_x = index * (workspace_clone.width - 150);
				var dest_x = index * (workspace_clone.width - 220);

				if (index == active_index) {
					active_x = dest_x;
					workspace_clone.related_thumb_workspace.select (true);
				} else {
					workspace_clone.related_thumb_workspace.select (false);
				}

				workspace_clone.save_easing_state ();
				workspace_clone.set_easing_duration (animate ? 200 : 0);
				workspace_clone.x = dest_x;
				workspace_clone.restore_easing_state ();
			}

			flow_workspaces.set_easing_duration (animate ?
				AnimationSettings.get_default ().workspace_switch_duration : 0);
			flow_workspaces.x = -active_x;

			reposition_thumb_workspaces (animate);
		}

		// TODO: layout
		void reposition_thumb_workspaces (bool animate)
		{
			var active_index = screen.get_active_workspace ().index ();

			thumb_workspaces.save_easing_state ();

			thumb_workspaces.set_easing_mode (AnimationMode.EASE_OUT_QUAD);
			thumb_workspaces.set_easing_duration (animate ? 200 : 0);

			// make sure the active workspace's thumbnail clone is always visible
			var thumb_workspaces_width = thumb_workspaces.calculate_total_width ();
			if (thumb_workspaces_width > width) {
				thumb_workspaces.x = (-active_index * (DeepinWorkspaceThumbCloneContainer.SPACING + DeepinWorkspaceThumbClone.SIZE) + width / 2)
				.clamp (width - thumb_workspaces_width - 64, 64);
			} else {
				thumb_workspaces.x = width / 2 - thumb_workspaces_width / 2;
			}

			thumb_workspaces.restore_easing_state ();
		}

		void add_workspace (int num)
		{
			var workspace = new DeepinWorkspaceFlowClone (screen.get_workspace_by_index (num));
			workspace.window_activated.connect (activate_window);
			workspace.selected.connect (activate_workspace);

			flow_workspaces.insert_child_at_index (workspace, num);
			thumb_workspaces.add_thumb (workspace.related_thumb_workspace);

			update_positions (opened);

			if (opened) {
				workspace.open ();
			}
		}

		void remove_workspace (int num)
		{
			DeepinWorkspaceFlowClone? workspace = null;

			// FIXME is there a better way to get the removed workspace?
			unowned List<Meta.Workspace> existing_workspaces = screen.get_workspaces ();

			foreach (var child in flow_workspaces.get_children ()) {
				unowned DeepinWorkspaceFlowClone clone = (DeepinWorkspaceFlowClone) child;
				if (existing_workspaces.index (clone.workspace) < 0) {
					workspace = clone;
					break;
				}
			}

			if (workspace == null) {
				return;
			}

			workspace.window_activated.disconnect (activate_window);
			workspace.selected.disconnect (activate_workspace);

			thumb_workspaces.remove_thumb (workspace.related_thumb_workspace);

			workspace.destroy ();

			update_positions (opened);
		}

		/**
		 * Activates the workspace of a DeepinWorkspaceFlowClone
		 *
		 * @param close_view Whether to close the view as well. Will only be considered
		 *                   if the workspace is also the currently active workspace.
		 *                   Otherwise it will only be made active, but the view won't be
		 *                   closed.
		 */
		void activate_workspace (DeepinWorkspaceFlowClone clone, bool close_view)
		{
			close_view = close_view && screen.get_active_workspace () == clone.workspace;

			clone.workspace.activate (screen.get_display ().get_current_time ());

			if (close_view) {
				toggle ();
			}
		}

		/**
		 * Collect key events, mainly for redirecting them to the WindowCloneContainers to
		 * select the active window.
		 */
		public override bool key_press_event (Clutter.KeyEvent event)
		{
			switch (event.keyval) {
				case Clutter.Key.Escape:
					if (opened) {
						toggle ();
					}
					break;
				case Clutter.Key.Down:
					select_window (MotionDirection.DOWN);
					break;
				case Clutter.Key.Up:
					select_window (MotionDirection.UP);
					break;
				case Clutter.Key.Left:
					select_window (MotionDirection.LEFT);
					break;
				case Clutter.Key.Right:
					select_window (MotionDirection.RIGHT);
					break;
				case Clutter.Key.Return:
				case Clutter.Key.KP_Enter:
					get_active_workspace_clone ().window_container.activate_selected_window ();
					break;
			}

			return false;
		}

		/**
		 * Inform the current WindowCloneContainer that we want to move the focus in
		 * a specific direction.
		 *
		 * @param direction The direction in which to move the focus to
		 */
		void select_window (MotionDirection direction)
		{
			get_active_workspace_clone ().window_container.select_next_window (direction);
		}

		/**
		 * Finds the active DeepinWorkspaceFlowClone
		 *
		 * @return The active DeepinWorkspaceFlowClone
		 */
		DeepinWorkspaceFlowClone get_active_workspace_clone ()
		{
			foreach (var child in flow_workspaces.get_children ()) {
				unowned DeepinWorkspaceFlowClone workspace_clone = (DeepinWorkspaceFlowClone) child;
				if (workspace_clone.workspace == screen.get_active_workspace ()) {
					return workspace_clone;
				}
			}

			assert_not_reached ();
		}

		void activate_window (Meta.Window window)
		{
			var time = screen.get_display ().get_current_time ();
			var workspace = window.get_workspace ();

			if (workspace != screen.get_active_workspace ()) {
				workspace.activate (time);
			} else {
				window.activate (time);
				toggle ();
			}
		}

		/**
		 * {@inheritDoc}
		 */
		public bool is_opened ()
		{
			return opened;
		}

		/**
		 * {@inheritDoc}
		 */
		public void open (HashTable<string,Variant>? hints = null)
		{
			if (opened) {
				return;
			}

			toggle ();
		}

		/**
		 * {@inheritDoc}
		 */
		public void close ()
		{
			if (!opened) {
				return;
			}

			toggle ();
		}

		/**
		 * Toggles the view open or closed. Takes care of all the wm related tasks, like
		 * starting the modal mode and hiding the WindowGroup. Finally tells all components
		 * to animate to their positions.
		 */
		void toggle ()
		{
			if (animating) {
				return;
			}

			animating = true;

			opened = !opened;
			var opening = opened;

			foreach (var container in window_containers_monitors) {
				if (opening) {
					container.visible = true;
					container.open ();
				} else {
					container.close ();
				}
			}

			if (opening) {
				modal_proxy = wm.push_modal ();
				modal_proxy.keybinding_filter = keybinding_filter;

				wm.background_group.hide ();
				wm.window_group.hide ();
				wm.top_window_group.hide ();
				show ();
				grab_key_focus ();

				// TODO: layout
				// thumb_workspaces.y = height - DeepinWorkspaceFlowClone.BOTTOM_OFFSET + 20;
				thumb_workspaces.y = 10;
			} else {
				DragDropAction.cancel_all_by_id ("deepin-multitaskingview-window");
			}

			// find active workspace clone and raise it, so there are no overlaps while transitioning
			DeepinWorkspaceFlowClone? active_workspace = null;
			var active = screen.get_active_workspace ();
			foreach (var child in flow_workspaces.get_children ()) {
				unowned DeepinWorkspaceFlowClone workspace = (DeepinWorkspaceFlowClone) child;
				if (workspace.workspace == active) {
					active_workspace = workspace;
					break;
				}
			}
			if (active_workspace != null) {
				flow_workspaces.set_child_above_sibling (active_workspace, null);
			}

			flow_workspaces.remove_all_transitions ();
			foreach (var child in flow_workspaces.get_children ()) {
				child.remove_all_transitions ();
			}

			update_positions (false);

			foreach (var child in flow_workspaces.get_children ()) {
				unowned DeepinWorkspaceFlowClone workspace = (DeepinWorkspaceFlowClone) child;
				if (opening) {
					workspace.open ();
				} else {
					workspace.close ();
				}
			}

			if (opening) {
				unowned List<WindowActor> actors = Compositor.get_window_actors (screen);

				foreach (var actor in actors) {
					const int MAX_OFFSET = 100;

					var window = actor.get_meta_window ();

					if (window.window_type != WindowType.DOCK) {
						continue;
					}

					var clone = new SafeWindowClone (window, true);
					clone.opacity = 0;
					dock_clones.add_child (clone);
				}
			} else {
				foreach (var child in dock_clones.get_children ()) {
					var dock = (Clone) child;

					dock.set_easing_duration (ANIMATION_DURATION);
					dock.set_easing_mode (ANIMATION_MODE);
					dock.opacity = 255;
				}
			}

			if (!opening) {
				Timeout.add (ANIMATION_DURATION, () => {
					foreach (var container in window_containers_monitors) {
						container.visible = false;
					}

					hide ();

					wm.background_group.show ();
					wm.window_group.show ();
					wm.top_window_group.show ();

					dock_clones.destroy_all_children ();

					wm.pop_modal (modal_proxy);

					animating = false;

					return false;
				});
			} else {
				Timeout.add (ANIMATION_DURATION, () => {
					animating = false;
					return false;
				});
			}
		}

		bool keybinding_filter (KeyBinding binding)
		{
			var name = binding.get_name ();
			switch (name) {
			case "preview-workspace":
				return false;
			}

			var action = Prefs.get_keybinding_action (name);
			switch (action) {
			case KeyBindingAction.WORKSPACE_1:
			case KeyBindingAction.WORKSPACE_2:
			case KeyBindingAction.WORKSPACE_3:
			case KeyBindingAction.WORKSPACE_4:
			case KeyBindingAction.WORKSPACE_5:
			case KeyBindingAction.WORKSPACE_6:
			case KeyBindingAction.WORKSPACE_7:
			case KeyBindingAction.WORKSPACE_8:
			case KeyBindingAction.WORKSPACE_9:
			case KeyBindingAction.WORKSPACE_10:
			case KeyBindingAction.WORKSPACE_11:
			case KeyBindingAction.WORKSPACE_12:
			case KeyBindingAction.WORKSPACE_LEFT:
			case KeyBindingAction.WORKSPACE_RIGHT:
			case KeyBindingAction.WORKSPACE_UP:
			case KeyBindingAction.WORKSPACE_DOWN:
#if HAS_MUTTER314
			case KeyBindingAction.WORKSPACE_LAST:
#endif
				return false;
			default:
				return true;
			}
		}
	}
}
