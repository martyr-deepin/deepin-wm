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
	 * The central class for the DeepinMultitaskingView which takes care of preparing the wm,
	 * opening the components and holds containers for the icon groups, the WorkspaceClones 
	 */
	public class DeepinMultitaskingView : Actor, ActivatableComponent
	{
		public const AnimationMode TOGGLE_MODE = AnimationMode.EASE_OUT_QUINT;
		public const int WORKSPACE_SWITCH_DURATION = 400;
		public const AnimationMode WORKSPACE_SWITCH_MODE = AnimationMode.EASE_OUT_QUINT;
		public const int WORKSPACE_FADE_DURATION = 400;
		public const AnimationMode WORKSPACE_FADE_MODE = AnimationMode.EASE_IN_OUT_CUBIC;

		const int SMOOTH_SCROLL_DELAY = 500;

		/**
		 * The percent value between workspace clones' horizontal offset and monitor's height.
		 */
		public const float HORIZONTAL_OFFSET_PERCENT = 0.044f;

		/**
		 * The percent value between flow workspace's top offset and monitor's height.
		 */
		public const float FLOW_WORKSPACE_TOP_OFFSET_PERCENT = 0.211f;

		/**
		 * The percent value between distance of flow workspaces and its width.
		 */
		public const float FLOW_WORKSPACE_DISTANCE_PERCENT = 0.089f;

		public WindowManager wm { get; construct; }

		Meta.Screen screen;
		ModalProxy modal_proxy;
		bool opened = false;
		bool toggling = false;
		bool animating = false;
		int toggle_duration = 450;
        // indicate that next switch signal is caused by a workspace removal
        // use this is optimize animation process
        bool expected_workspace_switch_by_removal = false;
        bool workspace_removing = false;

		bool is_smooth_scrolling = false;

        List<BlurredBackgroundActor> background_actors;

        Actor dark_mask;
        BackgroundSource background_source;
		uint changed_handler = -1;

		Actor dock_clones;
		Actor flow_container;
		DeepinWorkspaceThumbContainer thumb_container;

		public DeepinMultitaskingView (WindowManager wm)
		{
			Object (wm: wm);
		}

		construct
		{
			visible = false;
			reactive = true;
			clip_to_allocation = true;

			unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
			toggle_duration = animation_settings.multitasking_toggle_duration;

			opened = false;
			screen = wm.get_screen ();

            background_source = BackgroundCache.get_default ().get_background_source (
				screen, BackgroundManager.BACKGROUND_SCHEMA, BackgroundManager.EXTRA_BACKGROUND_SCHEMA);
			background_source.changed.connect ((indexes) => {
                var active_index = screen.get_active_workspace ().index ();
                foreach (var idx in indexes) {
                    if (idx == active_index) {
                        update_background_actors ();
                        break;
                    }
                }
			});

            dark_mask = new DeepinCssStaticActor("deepin-window-manager-background-mask");

			flow_container = new Actor ();

			thumb_container = new DeepinWorkspaceThumbContainer (screen);

			thumb_container.workspace_closing.connect ((workspace) => {
                if (screen.get_active_workspace () == workspace) {
                    expected_workspace_switch_by_removal = true;
                }
			});

			dock_clones = new Actor ();

            add_child (dark_mask);
			add_child (thumb_container);
			add_child (flow_container);
			add_child (dock_clones);

			foreach (var workspace in screen.get_workspaces ()) {
				add_workspace (workspace.index ());
			}

			screen.workspace_added.connect (add_workspace);
			screen.workspace_removed.connect (remove_workspace);
			screen.workspace_switched.connect_after (on_workspace_switched);
            screen.monitors_changed.connect (on_monitors_changed);
            on_monitors_changed ();

			Prefs.add_listener ((pref) => {
				if (Prefs.get_dynamic_workspaces () ||
					(pref != Preference.DYNAMIC_WORKSPACES && pref != Preference.NUM_WORKSPACES)) {
					return;
				}

                if (workspace_removing) return;

				Idle.add (() => {
					unowned List<Workspace> existing_workspaces = screen.get_workspaces ();

					foreach (var child in flow_container.get_children ()) {
						unowned DeepinWorkspaceFlowClone flow_workspace =
							(DeepinWorkspaceFlowClone)child;
						if (existing_workspaces.index (flow_workspace.workspace) < 0) {
							flow_workspace.window_activated.disconnect (activate_window);
							flow_workspace.selected.disconnect (activate_workspace);

							thumb_container.remove_workspace (
								flow_workspace.thumb_workspace);

							flow_workspace.destroy ();
						}
					}

					// FIXME: panic if workspace num changed by third party tools like "wmctrl -n 4"

					return false;
				});
			});
		}

		~DeepinMultitaskingView ()
		{
			background_source.changed.disconnect (update_background_actors);
            screen.monitors_changed.disconnect (on_monitors_changed);
			screen.workspace_added.disconnect (add_workspace);
			screen.workspace_removed.disconnect (remove_workspace);
			screen.workspace_switched.disconnect (on_workspace_switched);
		}

		public void connect_key_focus_out_signal ()
		{
			/**
			 * We generally assume that when the key-focus-out signal is emitted a different
			 * component was opened, so we close in that case. And we should listen property changed
			 * for "key-focus" in stage instead of overriding key_focus_out, or could not get the
			 * right key focus actor.
			 */
			get_stage ().notify["key-focus"].connect (() => {
				if (opened && !contains (get_stage ().key_focus)) {
					toggle ();
				}
			});
		}

        void update_background_actors ()
        {
            var active_index = screen.get_active_workspace ().index ();
            foreach (var background_actor in background_actors) {
                var background = background_source.get_background (background_actor.monitor, active_index);

                background_actor.background = background.background;
                background_actor.set_rounds (8);
                background_actor.set_radius (9);

                var monitor = screen.get_monitor_geometry (background_actor.monitor);
                background_actor.set_size (monitor.width, monitor.height);
                background_actor.set_position (monitor.x, monitor.y);
            }
        }

        void on_monitors_changed ()
        {
            var primary = screen.get_primary_monitor ();
            var primary_geometry = screen.get_monitor_geometry (primary);

            set_position (primary_geometry.x, primary_geometry.y);
            set_size (primary_geometry.width, primary_geometry.height);

            foreach (var background_actor in background_actors) {
				background_actor.destroy ();
            }
                        
            for (var monitor = 0; monitor < screen.get_n_monitors (); monitor++) {
                var background_actor = new BlurredBackgroundActor (screen, monitor);
                background_actors.append (background_actor);
				background_actor.visible = opened;
                wm.ui_group.insert_child_below (background_actor, null);
            }

            update_background_actors ();

            dark_mask.set_size (primary_geometry.width, primary_geometry.height);
            update_positions (true);

        }

		void on_workspace_switched (int from, int to, Meta.MotionDirection direction)
		{
            foreach (var background_actor in background_actors) {
                var background = background_source.get_background (background_actor.monitor, to);
                background_actor.background = background.background;
            }

            thumb_container.select_workspace (screen.get_active_workspace_index (), true);
            if (expected_workspace_switch_by_removal) {
                expected_workspace_switch_by_removal = false;
                return;
            }

			update_positions (opened, direction);
		}

		/**
		 * Scroll through flow_container.
		 */
		public override bool scroll_event (ScrollEvent scroll_event)
		{
			if (scroll_event.direction != ScrollDirection.SMOOTH) {
				return false;
			}

			double dx, dy;
#if VALA_0_32
			scroll_event.get_scroll_delta (out dx, out dy);
#else
			var event = (Event*)(&scroll_event);
			event->get_scroll_delta (out dx, out dy);
#endif

			var direction = MotionDirection.LEFT;

			// concept from maya to detect mouse wheel and proper smooth scroll and prevent too much
			// repetition on the events
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
		 * Places the WorkspaceClones, moves the view so that the active one is shown and does the
		 * same for the ThumbWorkspaces.
		 *
		 * @param animate Whether to animate the movement or have all elements take their positions
		 *                immediately.
		 */
		void update_positions (bool animate, Meta.MotionDirection direction = Meta.MotionDirection.LEFT)
		{
			var active_index = screen.get_active_workspace_index ();

			int long_delay = 100;
			int short_delay = 100;
			foreach (var child in flow_container.get_children ()) {
				var flow_workspace = child as DeepinWorkspaceFlowClone;
				var index = flow_workspace.workspace.index ();

				int delay = 0;
				if (direction == Meta.MotionDirection.LEFT) {
					if (index < active_index) {
						delay = long_delay;
					} else if (index == active_index) {
						delay = short_delay;
					} else if (index > active_index) {
						delay = 0;
					}
				} else if (direction == Meta.MotionDirection.RIGHT) {
					if (index < active_index) {
						delay = 0;
					} else if (index == active_index) {
						delay = short_delay;
					} else if (index > active_index) {
						delay = long_delay;
					}
				}

				// use workspace index to place flow workspaces clones instead of the index of
				// container, for that the active workspace always make above others.
				place_flow_workspace (child, index, animate, delay);
			}

			if (animate) {
				animating = true;
				Timeout.add (WORKSPACE_SWITCH_DURATION + long_delay, () => {
					animating = false;
					return false;
				});
			}
		}

		void place_flow_workspace (Actor child, int index, bool animate, int delay)
		{
			if (animate) {
				Timeout.add (delay, () => {
					do_place_flow_workspace (child, index, animate);
					return false;
				});
			} else {
				do_place_flow_workspace (child, index, animate);
			}
		}

		void do_place_flow_workspace (Actor child, int index, bool animate)
		{
			ActorBox child_box = get_flow_workspace_layout_box (child, index);

			child.save_easing_state ();

			child.set_easing_mode (WORKSPACE_SWITCH_MODE);
			child.set_easing_duration (animate ? WORKSPACE_SWITCH_DURATION : 0);
			child.x = child_box.get_x ();
			child.y = child_box.get_y ();

			child.restore_easing_state ();
		}

		ActorBox get_flow_workspace_layout_box (Actor child, int index)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);
			var active_index = screen.get_active_workspace ().index ();
			var box = ActorBox ();

			float child_x =
				(index - active_index) * (monitor_geom.width * (1 - FLOW_WORKSPACE_DISTANCE_PERCENT * 2));
			float child_y = 0;

			box.set_size (monitor_geom.width, monitor_geom.height);
			box.set_origin (child_x, child_y);

			return box;
		}

		void add_workspace (int index)
		{
			var flow_workspace = new DeepinWorkspaceFlowClone (
				screen.get_workspace_by_index (index));
			if (opened) {
				flow_workspace.open (false);
			}
			flow_workspace.window_activated.connect (activate_window);
			flow_workspace.selected.connect (activate_workspace);

			thumb_container.add_workspace (flow_workspace.thumb_workspace,
										   () => update_positions (opened));

			flow_workspace.opacity = 0;
			if (opened) {
				flow_workspace.scale_in (false);
			}
			flow_container.add_child (flow_workspace);
			do_place_flow_workspace (flow_workspace, index, false);

			animating = true;
			DeepinUtils.start_fade_in_opacity_animation (flow_workspace,
														 WORKSPACE_FADE_DURATION,
														 WORKSPACE_FADE_MODE);
			Timeout.add (WORKSPACE_FADE_DURATION, () => {
				animating = false;
				return false;
			});
		}

		void remove_workspace (int index)
		{
            workspace_removing = true;

			DeepinWorkspaceFlowClone? flow_workspace = null;

			// FIXME is there a better way to get the removed workspace?
			unowned List<Meta.Workspace> existing_workspaces = screen.get_workspaces ();

			foreach (var child in flow_container.get_children ()) {
				unowned DeepinWorkspaceFlowClone child_workspace = (DeepinWorkspaceFlowClone)child;
				if (existing_workspaces.index (child_workspace.workspace) < 0) {
					flow_workspace = child_workspace;
					break;
				}
			}

			if (flow_workspace == null) {
				return;
			}

			flow_workspace.window_activated.disconnect (activate_window);
			flow_workspace.selected.disconnect (activate_workspace);

			thumb_container.remove_workspace (flow_workspace.thumb_workspace);
            flow_workspace.reparent (this);

			DeepinUtils.start_fade_out_animation ( flow_workspace,
				DeepinMultitaskingView.WORKSPACE_FADE_DURATION,
				DeepinMultitaskingView.WORKSPACE_FADE_MODE, 
                () => {
                    update_positions (opened);
                    update_background_actors ();
                }, 0.3);

            flow_workspace.transitions_completed.connect(() => {
                flow_workspace.destroy ();
                workspace_removing = false;

            });
		}

		/**
		 * Activates the workspace of a DeepinWorkspaceFlowClone
		 *
		 * @param close_view Whether to close the view as well. Will only be considered if the
		 *                   workspace is also the currently active workspace.  Otherwise it will
		 *                   only be made active, but the view won't be closed.
		 */
		void activate_workspace (DeepinWorkspaceFlowClone flow_workspace, bool close_view)
		{
			close_view = close_view && screen.get_active_workspace () == flow_workspace.workspace;

			flow_workspace.workspace.activate (screen.get_display ().get_current_time ());

			if (close_view) {
				toggle ();
			}
		}

        void start_nudge_effect_for (Actor actor, MotionDirection direction)
        {
            if (actor.get_transition ("nudge") != null) {
                return;
            }

            var dest = (direction == MotionDirection.LEFT ? 32.0f : -32.0f);

            double[] keyframes = { 0.5, 1.0 };
            GLib.Value[] x = { dest, 0.0f };
            Clutter.AnimationMode[] modes = {Clutter.AnimationMode.EASE_IN_QUAD,
                Clutter.AnimationMode.EASE_OUT_QUAD};

            var nudge = new Clutter.KeyframeTransition ("x");
            nudge.duration = 450;
            nudge.remove_on_complete = true;
            nudge.set_from_value (0.0f);
            nudge.set_to_value (0.0f);
            nudge.set_key_frames (keyframes);
            nudge.set_values (x);
            nudge.set_modes (modes);

            actor.add_transition ("nudge", nudge);
        }

        void start_nudge_effect (MotionDirection direction)
        {
            start_nudge_effect_for (thumb_container, direction);
            start_nudge_effect_for (flow_container, direction);
        }

		/**
		 * Collect key events, mainly for redirecting them to the WindowCloneContainers to select
		 * the active window.
		 */
		public override bool key_press_event (Clutter.KeyEvent event)
		{
			if (toggling) {
				// disable key event when playing toggle animation
				return false;
			}
			switch (event.keyval) {
			case Clutter.Key.Escape:
				if (opened) {
					toggle ();
				}
				break;
			case Clutter.Key.@0:
				DeepinUtils.switch_to_workspace (screen, 9);
				break;
			case Clutter.Key.@1:
				DeepinUtils.switch_to_workspace (screen, 0);
				break;
			case Clutter.Key.@2:
				DeepinUtils.switch_to_workspace (screen, 1);
				break;
			case Clutter.Key.@3:
				DeepinUtils.switch_to_workspace (screen, 2);
				break;
			case Clutter.Key.@4:
				DeepinUtils.switch_to_workspace (screen, 3);
				break;
			case Clutter.Key.@5:
				DeepinUtils.switch_to_workspace (screen, 4);
				break;
			case Clutter.Key.@6:
				DeepinUtils.switch_to_workspace (screen, 5);
				break;
			case Clutter.Key.@7:
				DeepinUtils.switch_to_workspace (screen, 6);
				break;
			case Clutter.Key.@8:
				DeepinUtils.switch_to_workspace (screen, 7);
				break;
			case Clutter.Key.@9:
				DeepinUtils.switch_to_workspace (screen, 8);
				break;
			case Clutter.Key.Home:
			case Clutter.Key.KP_Home:
				DeepinUtils.switch_to_workspace (screen, 0);
				break;
			case Clutter.Key.End:
			case Clutter.Key.KP_End:
				DeepinUtils.switch_to_workspace (screen, Prefs.get_num_workspaces () - 1);
				break;
			case Clutter.Key.Tab:
			case Clutter.Key.ISO_Left_Tab:
				bool backward = (event.modifier_state & ModifierType.SHIFT_MASK) != 0;
				select_window_by_order (backward);
				break;
			case Clutter.Key.Left:
                var screen = wm.get_screen ();
                var active_workspace = screen.get_active_workspace ();
                var neighbor = active_workspace.get_neighbor (MotionDirection.LEFT);

                if (neighbor != active_workspace) {
                    wm.switch_to_next_workspace (MotionDirection.LEFT);
                } else {
                    start_nudge_effect (MotionDirection.LEFT);
                }

				break;
			case Clutter.Key.Right:
                var screen = wm.get_screen ();
                var active_workspace = screen.get_active_workspace ();
                var neighbor = active_workspace.get_neighbor (MotionDirection.RIGHT);

                if (neighbor != active_workspace) {
                    wm.switch_to_next_workspace (MotionDirection.RIGHT);
                } else {
                    start_nudge_effect (MotionDirection.RIGHT);
                }
				break;
			case Clutter.Key.plus:
			case Clutter.Key.equal:
			case Clutter.Key.KP_Add:
				animating = true;
				thumb_container.append_new_workspace ();
				Timeout.add (WORKSPACE_FADE_DURATION, () => {
					animating = false;
					return false;
				});
				break;
			case Clutter.Key.minus:
			case Clutter.Key.KP_Subtract:
				var i = screen.get_active_workspace_index ();
				var thumb_workspace = thumb_container.get_child_at_index (i);
				(thumb_workspace as DeepinWorkspaceThumbClone).remove_workspace ();
				break;
			case Clutter.Key.Return:
			case Clutter.Key.KP_Enter:
				if (get_active_workspace_clone ().window_container.has_selected_window ()) {
					get_active_workspace_clone ().window_container.activate_selected_window ();
				} else {
					if (opened) {
						toggle ();
					}
				}
				break;
			case Clutter.Key.Delete:
			case Clutter.Key.KP_Delete:
			case Clutter.Key.BackSpace:
				if (get_active_workspace_clone ().window_container.has_selected_window ()) {
					get_active_workspace_clone ().window_container.close_active_window ();
				}
				break;
			}

			return false;
		}

		/**
		 * Inform the current WindowCloneContainer that we want to move the window focus in.
		 *
		 * @param backward The window order in which to looking for.
		 */
		void select_window_by_order (bool backward)
		{
			get_active_workspace_clone ().window_container.select_window_by_order (backward);
		}

		/**
		 * Inform the current WindowCloneContainer that we want to move the focus in a specific
		 * direction.
		 *
		 * @param direction The direction in which to move the focus to
		 */
		void select_window_by_direction (MotionDirection direction)
		{
			get_active_workspace_clone ().window_container.select_window_by_direction (direction);
		}

		/**
		 * Finds the active DeepinWorkspaceFlowClone.
		 *
		 * @return The active DeepinWorkspaceFlowClone
		 */
		DeepinWorkspaceFlowClone get_active_workspace_clone ()
		{
			foreach (var child in flow_container.get_children ()) {
				unowned DeepinWorkspaceFlowClone flow_workspace = (DeepinWorkspaceFlowClone)child;
				if (flow_workspace.workspace == screen.get_active_workspace ()) {
					return flow_workspace;
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
		 *
		 */
		public bool is_toggling ()
		{
			return toggling;
		}

		/**
		 * {@inheritDoc}
		 */
		public void open (HashTable<string, Variant>? hints = null)
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

        public void reorder_workspace (Meta.Workspace ws, int new_index)
        {
            background_source.reorder_workspace_background (ws.index (), new_index);
            wm.get_screen().reorder_workspace (ws, new_index, 0);

			flow_container.remove_all_transitions ();
			foreach (var child in flow_container.get_children ()) {
				child.remove_all_transitions ();
			}
			update_positions (false);
            update_background_actors ();
        }
         
		/**
		 * Toggles the view open or closed. Takes care of all the wm related tasks, like starting
		 * the modal mode and hiding the WindowGroup. Finally tells all components to animate to
		 * their positions.
		 */
		void toggle ()
		{
			if (animating) {
				// ignore toggle request if workspac switching
				return;
			}

			if (toggling) {
				return;
			}

			toggling = true;

			opened = !opened;
			var opening = opened;

			if (opening) {
				modal_proxy = wm.push_modal ();
				modal_proxy.keybinding_filter = keybinding_filter;

				wm.window_group.hide ();
				wm.top_window_group.hide ();
				show ();
				grab_key_focus ();
			} else {
				DragDropAction.cancel_all_by_id ("deepin-multitaskingview-window");
                thumb_container.remove_transition ("nudge");
                flow_container.remove_transition ("nudge");
			}

			// find active workspace clone and raise it, so there are no overlaps while
			// transitioning
			DeepinWorkspaceFlowClone? active_workspace = null;
			var active = screen.get_active_workspace ();
			foreach (var child in flow_container.get_children ()) {
				unowned DeepinWorkspaceFlowClone child_workspace = (DeepinWorkspaceFlowClone)child;
				if (child_workspace.workspace == active) {
					active_workspace = child_workspace;
					break;
				}
			}
			if (active_workspace != null) {
				flow_container.set_child_above_sibling (active_workspace, null);
			}

			flow_container.remove_all_transitions ();
			foreach (var child in flow_container.get_children ()) {
				child.remove_all_transitions ();
			}

			if (opening) {
				thumb_container.open ();
			} else {
				thumb_container.close ();
			}

			update_positions (false);
            thumb_container.select_workspace (screen.get_active_workspace_index (), false);

			var monitor_geom = screen.get_monitor_geometry (screen.get_primary_monitor ());
			var thumb_y_value = GLib.Value (typeof (float));
			if (opening) {
				thumb_y_value.set_float ((monitor_geom.height * HORIZONTAL_OFFSET_PERCENT));
			} else {
                thumb_y_value.set_float (-(monitor_geom.height * FLOW_WORKSPACE_TOP_OFFSET_PERCENT));
			}

			DeepinUtils.start_animation_group (thumb_container, "toggle", toggle_duration,
											   DeepinUtils.clutter_set_mode_ease_out_quint,
											   "y", &thumb_y_value);

			foreach (var child in flow_container.get_children ()) {
				unowned DeepinWorkspaceFlowClone flow_workspace = (DeepinWorkspaceFlowClone)child;
				if (opening) {
					flow_workspace.open ();
				} else {
					flow_workspace.close ();
				}
			}

			if (opening) {
				unowned List<WindowActor> actors = Compositor.get_window_actors (screen);

				foreach (var actor in actors) {
					// const int MAX_OFFSET = 100;

					var window = actor.get_meta_window ();

					if (window.window_type != WindowType.DOCK) {
						continue;
					}

					var dock = new SafeWindowClone (window, true);
					dock.x = actor.x;
					dock.y = actor.y;
					dock.opacity = 0;
					dock_clones.add_child (dock);
				}

                foreach (var background_actor in background_actors) {
                    background_actor.visible = opened;
                }
			} else {
				foreach (var child in dock_clones.get_children ()) {
					var dock = (Clone)child;

					dock.set_easing_duration (toggle_duration);
					dock.set_easing_mode (TOGGLE_MODE);
					dock.opacity = 255;
				}
			}

			if (!opening) {
				Timeout.add (toggle_duration, () => {
					hide ();

                    foreach (var background_actor in background_actors) {
                        background_actor.visible = opened;
                    }

					wm.window_group.show ();
					wm.top_window_group.show ();

					dock_clones.destroy_all_children ();

					wm.pop_modal (modal_proxy);

					toggling = false;

					return false;
				});
			} else {
				Timeout.add (toggle_duration, () => {
					toggling = false;
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
			case KeyBindingAction.WORKSPACE_UP:
			case KeyBindingAction.WORKSPACE_DOWN:
#if HAS_MUTTER314
			case KeyBindingAction.WORKSPACE_LAST:
#endif
				return false;
			case KeyBindingAction.WORKSPACE_LEFT:
			case KeyBindingAction.WORKSPACE_RIGHT:
                /* disable this for nudge effect */
                return true;
			default:
				return true;
			}
		}
	}
}
