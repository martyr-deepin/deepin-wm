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
	 * Container which controls the layout of a set of window clones. The clones will be placed
	 * in rows and columns.
	 */
	public class DeepinWindowFlowContainer : DeepinWindowBaseContainer
	{
		public int padding_top { get; set; default = 12; }
		public int padding_left { get; set; default = 12; }
		public int padding_right { get; set; default = 12; }
		public int padding_bottom { get; set; default = 12; }

		/**
		 * Own all window positions to find next or preview window.
		 */
		List<InternalUtils.TilableWindow?> window_positions;

		public DeepinWindowFlowContainer (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		/**
		 * {@inheritDoc}
		 */
		public override void on_actor_added (Actor new_actor)
		{
			// apply new child only when calculating positions success
			if (update_window_positions ()) {
				base.on_actor_added (new_actor);
			}
	    }

		/**
		 * {@inheritDoc}
		 */
		public override void do_select_clone (DeepinWindowClone window_clone, bool select,
											  bool animate = true)
		{
			window_clone.set_select (select, animate);
		}

		/**
		 * {@inheritDoc}
		 */
		public override void relayout (bool selecting = false)
		{
			if (!opened) {
				return;
			}

			if (!update_window_positions ()) {
				return;
			}

			foreach (var child in get_children ()) {
				var window_clone = child as DeepinWindowClone;
				var box = get_layout_box_for_window (window_clone);
				var rect = DeepinUtils.new_rect_for_actor_box (box);
				window_clone.take_slot (rect, true, selecting);
			}
		}

		/**
		 * {@inheritDoc}
		 */
		public override ActorBox get_layout_box_for_window (DeepinWindowClone window_clone)
		{
			ActorBox box;
			foreach (var tilable in window_positions) {
				var w = tilable.id as DeepinWindowClone;
				if (window_clone == w) {
					box = DeepinUtils.new_actor_box_for_rect (tilable.rect);
					DeepinUtils.scale_actor_box_in_center (ref box, 0.9f);
					if (!window_clone.is_selected ()) {
						DeepinUtils.scale_actor_box_in_center (ref box, 0.9f);
					}
					return box;
				}
			}
			return {};
		}

		/**
		 * When opened the WindowClones will animate to a clone layout
		 */
		public override void open (Window? focus_window = null)
		{
			base.open (focus_window);

			select_clone (get_clone_for_window (focus_window), false);

			var screen = workspace.get_screen ();
			foreach (var window in get_children ()) {
				var window_clone = window as DeepinWindowClone;

                if (screen.get_active_workspace () == workspace) {
                    window_clone.transition_to_original_state (false);
                    var shadow_effect = window_clone.get_effect ("shadow") as ShadowEffect;
                    if (shadow_effect != null) {
                        shadow_effect.shadow_opacity = DeepinWindowClone.SHADOW_OPACITY;
                    }
                } else {
                    window_clone.x = this.width / 2;
                    window_clone.y = this.height / 2;
                }

				window_clone.opacity = 255;
			}

			relayout ();
		}

		/**
		 * Calls the transition_to_original_state() function on each child to make them take their
		 * original locations again.
		 */
		public override void close ()
		{
			base.close ();

			foreach (var window in get_children ()) {
				var window_clone = window as DeepinWindowClone;
				window_clone.set_select (false);
				if ((workspace.get_screen ().get_active_workspace () == workspace) &&
					window_clone.window.showing_on_its_workspace ()) {
					window_clone.transition_to_original_state (true);
                    var shadow_effect = window_clone.get_effect ("shadow") as ShadowEffect;
                    if (shadow_effect != null) {
                        shadow_effect.shadow_opacity = 0;
                    }

				} else {
					DeepinUtils.start_fade_out_opacity_animation (
						window_clone, 300, AnimationMode.EASE_OUT_QUAD);
				}
			}
		}

		/**
		 * Calculate window positions for re-layout later.
		 *
		 * @return true if succes
		 */
		bool update_window_positions ()
		{
			var windows = new List <InternalUtils.TilableWindow?> ();
			foreach (var child in get_children ()) {
				unowned DeepinWindowClone window_clone = (DeepinWindowClone)child;
				windows.prepend ({ window_clone.window.get_frame_rect (), window_clone });
			}

			if (windows.length () < 1) {
				return false;
			}

			// make sure the windows are always in the same order so the algorithm doesn't give us
			// different slots based on stacking order, which can lead to windows flying around
			// weirdly
			windows.sort ((a, b) => {
				var seq_a = (a.id as DeepinWindowClone).window.get_stable_sequence ();
				var seq_b = (b.id as DeepinWindowClone).window.get_stable_sequence ();
				return (int)(seq_b - seq_a);
			});

			Meta.Rectangle area = { padding_left, padding_top,
									(int)width - padding_left - padding_right,
									(int)height - padding_top - padding_bottom };

			// reset window_positions
			window_positions = InternalUtils.calculate_grid_placement (area, windows, false);
			return true;
		}

		/**
		 * Select the next window.
		 *
		 * @param backward The window order in which to looking for.
		 */
		public void select_window_by_order (bool backward)
		{
			if (get_n_children () < 1) {
				return;
			}
			if (window_positions.length () < 1) {
				return;
			}

			var selected_clone = get_selected_clone ();

			// get current window index
			int index = -1;
			int tmp_index = 0;
			foreach (var tilable in window_positions) {
				unowned DeepinWindowClone window_clone = (DeepinWindowClone)tilable.id;
				if (window_clone == selected_clone) {
					index = tmp_index;
					break;
				}
				tmp_index++;
			}

			// search for next window
			DeepinWindowClone next_window = null;
			int next_index = -1;
			if (index < 0) {
				if (backward) {
					next_index = (int)window_positions.length () - 1;
				} else {
					next_index = 0;
				}
			} else {
				next_index = index;
				if (backward) {
					next_index--;
					if (next_index < 0) {
						next_index = (int)window_positions.length () - 1;
					}
				} else {
					next_index++;
					if (next_index >= (int)window_positions.length ()) {
						next_index = 0;
					}
				}
			}
			next_window = (DeepinWindowClone)window_positions.nth_data (next_index).id;

			select_clone (next_window);
		}

		/**
		 * Look for the next window in a direction and select it. Used for keyboard navigation.
		 *
		 * @param direction The MetaMotionDirection in which to search for windows for.
		 */
		public void select_window_by_direction (MotionDirection direction)
		{
			if (get_n_children () < 1) {
				return;
			}

			var selected_clone = get_selected_clone ();
			if (selected_clone == null) {
				select_clone ((DeepinWindowClone)get_child_at_index (0));
				return;
			}

			var current_rect = selected_clone.slot;

			DeepinWindowClone? closest = null;
			foreach (var child in get_children ()) {
				if (child == selected_clone) {
					continue;
				}

				var window_rect = ((DeepinWindowClone)child).slot;

				switch (direction) {
				case MotionDirection.LEFT:
					if (window_rect.x > current_rect.x) {
						continue;
					}

					// test for vertical intersection
					if (window_rect.y + window_rect.height > current_rect.y &&
						window_rect.y < current_rect.y + current_rect.height) {
						if (closest == null || closest.slot.x < window_rect.x) {
							closest = (DeepinWindowClone)child;
						}
					}
					break;
				case MotionDirection.RIGHT:
					if (window_rect.x < current_rect.x) {
						continue;
					}

					// test for vertical intersection
					if (window_rect.y + window_rect.height > current_rect.y &&
						window_rect.y < current_rect.y + current_rect.height) {
						if (closest == null || closest.slot.x > window_rect.x) {
							closest = (DeepinWindowClone)child;
						}
					}
					break;
				case MotionDirection.UP:
					if (window_rect.y > current_rect.y) {
						continue;
					}

					// test for horizontal intersection
					if (window_rect.x + window_rect.width > current_rect.x &&
						window_rect.x < current_rect.x + current_rect.width) {
						if (closest == null || closest.slot.y < window_rect.y) {
							closest = (DeepinWindowClone)child;
						}
					}
					break;
				case MotionDirection.DOWN:
					if (window_rect.y < current_rect.y) {
						continue;
					}

					// test for horizontal intersection
					if (window_rect.x + window_rect.width > current_rect.x &&
						window_rect.x < current_rect.x + current_rect.width) {
						if (closest == null || closest.slot.y > window_rect.y) {
							closest = (DeepinWindowClone)child;
						}
					}
					break;
				}
			}

			if (closest == null) {
				return;
			}

			select_clone (closest);
		}

		/**
		 * Emit the selected signal for the selected_clone.
		 */
		public void activate_selected_window ()
		{
			var selected_clone = get_selected_clone ();
			if (selected_clone != null) {
				selected_clone.activated ();
			}
		}

        public void close_active_window ()
        {
			var selected_clone = get_selected_clone ();
			if (selected_clone != null) {
                selected_clone.close_window ();
			}
        }
	}
}
