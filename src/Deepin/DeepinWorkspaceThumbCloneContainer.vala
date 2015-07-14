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
	 * This class contains the DeepinWorkspaceThumbClone at the top
	 * and will take care of displaying actors for inserting windows
	 * between the groups once implemented.
	 */
	public class DeepinWorkspaceThumbCloneContainer : Actor
	{
		/**
		 * The percent value between thumbnail workspace clone's width
		 * and monitor's width.
		 */
		public const float WORKSPACE_WIDTH_PERCENT = 0.12f;

		/**
		 * The percent value between distance of thumbnail workspace
		 * clones and monitor's width.
		 */
		const float SPACING_PERCENT = 0.02f;

		// TODO: animation
		const int ANIMATION_DURATION = 500;
		const AnimationMode ANIMATION_MODE = AnimationMode.EASE_OUT_QUAD;

		public Screen screen { get; construct; }

		Actor add_button;

		public DeepinWorkspaceThumbCloneContainer (Screen screen)
		{
			Object (screen: screen);

			add_button = new DeepinWorkspaceAddButton ();
			add_button.reactive = true;
			add_button.set_easing_duration (ANIMATION_DURATION);
			add_button.set_easing_mode (ANIMATION_MODE);
			add_button.button_press_event.connect (() => {
				DeepinUtils.append_new_workspace (screen);
				return false;
			});
		}

		public void add_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			// TODO: animation
			// workspace_clone.opacity = 0;
			workspace_clone.set_easing_duration (ANIMATION_DURATION);
			workspace_clone.set_easing_mode (ANIMATION_MODE);
			// workspace_clone.opacity = 255;

			var index = workspace_clone.workspace.index ();
			insert_child_at_index (workspace_clone, index);

			relayout ();
		}

		public void remove_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			remove_child (workspace_clone);

			// Prevent other workspaces' original name to be reset, so here set
			// them to gsettings again.
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).set_workspace_name ();
				}
			}

			relayout ();
		}

		public void relayout ()
		{
			setup_pluse_button ();

			var display = screen.get_display ();
			var monitor_geom = screen.get_monitor_geometry (screen.get_primary_monitor ());

			// calculate monitor width height ratio
			float monitor_whr = (float) monitor_geom.height / monitor_geom.width;

			y = (int) (monitor_geom.height * DeepinMultitaskingView.HORIZONTAL_OFFSET_PERCENT);

			float child_x = 0;
			float child_width = monitor_geom.width * WORKSPACE_WIDTH_PERCENT;;
			float child_height = child_width * monitor_whr;
			float child_spacing = monitor_geom.width * SPACING_PERCENT;
			var i = 0;
			foreach (var child in get_children ()) {
				child.x = child_x;
				child.y = 0;
				child.width = child_width;
				child.height = child_height;
				child_x += child_width + child_spacing;
				i++;

				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).get_workspace_name ();
				}
			}
		}

		/*
		 * Make pluse button visible if workspace number less than
		 * MAX_WORKSPACE_NUM.
		 */
		void setup_pluse_button ()
		{
			if (Prefs.get_num_workspaces () >= WindowManagerGala.MAX_WORKSPACE_NUM) {
				if (contains (add_button)) {
					remove_child (add_button);
				}
			} else {
				if (!contains (add_button)) {
					insert_child_at_index (add_button, get_n_children ());
				}
			}
		}
	}
}
