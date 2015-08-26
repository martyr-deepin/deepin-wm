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
	 * Will be put at end of workspace thumbnail list in DeepinMultitaskingView if number less than
	 * MAX_WORKSPACE_NUM.
	 */
	class DeepinWorkspaceAddButton : DeepinCssStaticActor
	{
		const double PLUS_SIZE = 32.0;
		const double PLUS_LINE_WIDTH = 2.0;

		public DeepinWorkspaceAddButton ()
		{
			base ("deepin-workspace-add-button");

			(content as Canvas).draw.connect (on_draw_content);
		}

		bool on_draw_content (Cairo.Context cr, int width, int height)
		{
			// draw tha plus button
			cr.move_to (width / 2 - PLUS_SIZE / 2, height / 2);
			cr.line_to (width / 2 + PLUS_SIZE / 2, height / 2);

			cr.move_to (width / 2, height / 2 - PLUS_SIZE / 2);
			cr.line_to (width / 2, height / 2 + PLUS_SIZE / 2);

			cr.set_line_width (PLUS_LINE_WIDTH);
			cr.set_source_rgba (0.5, 0.5, 0.5, 1.0);
			cr.stroke_preserve ();

			return false;
		}
	}

	/**
	 * This class contains the DeepinWorkspaceThumbClone at the top and will take care of displaying
	 * actors for inserting windows between the groups once implemented.
	 */
	public class DeepinWorkspaceThumbCloneContainer : Actor
	{
		/**
		 * The percent value between thumbnail workspace clone's width and monitor's width.
		 */
		public const float WORKSPACE_WIDTH_PERCENT = 0.12f;

		/**
		 * The percent value between distance of thumbnail workspace clones and monitor's width.
		 */
		const float SPACING_PERCENT = 0.02f;

		// TODO: animation
		const int LAYOUT_DURATION = 500;
		const AnimationMode LAYOUT_MODE = AnimationMode.EASE_OUT_QUAD;

		public Screen screen { get; construct; }

		Actor add_button;

		public DeepinWorkspaceThumbCloneContainer (Screen screen)
		{
			Object (screen: screen);

			add_button = new DeepinWorkspaceAddButton ();
			add_button.reactive = true;
			add_button.set_easing_duration (LAYOUT_DURATION);
			add_button.set_easing_mode (LAYOUT_MODE);
			add_button.button_press_event.connect (() => {
				DeepinUtils.append_new_workspace (screen);
				return false;
			});
		}

		public void add_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			// TODO: animation
			// workspace_clone.opacity = 0;
			// workspace_clone.set_easing_duration (LAYOUT_DURATION);
			// workspace_clone.set_easing_mode (LAYOUT_MODE);
			// workspace_clone.opacity = 255;

			var index = workspace_clone.workspace.index ();
			insert_child_at_index (workspace_clone, index);

			workspace_clone.workspace_name.grab_key_focus_for_name ();

			relayout ();
		}

		public void remove_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			remove_child (workspace_clone);

			// Prevent other workspaces' original name to be reset, so here set
			// them to gsettings again.
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).workspace_name.set_workspace_name ();
				}
			}

			relayout ();
		}

		public void relayout ()
		{
			setup_pluse_button ();

			var i = 0;
			foreach (var child in get_children ()) {
				child.save_easing_state ();

				child.set_easing_duration (LAYOUT_DURATION);

				place_child (child, i);
				i++;

				child.restore_easing_state ();

				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).workspace_name.get_workspace_name ();
				}
			}
		}

		public static void get_thumb_size (Screen screen, out float width, out float height)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			// calculate monitor width height ratio
			float monitor_whr = (float)monitor_geom.height / monitor_geom.width;

			width = monitor_geom.width * WORKSPACE_WIDTH_PERCENT;
			;
			height = width * monitor_whr;
		}

		void place_child (Actor child, int index)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			float child_x = 0;
			float child_y = 0;
			float child_spacing = monitor_geom.width * SPACING_PERCENT;

			float child_width, child_height = 0;
			get_thumb_size (screen, out child_width, out child_height);
			child_x = (child_width + child_spacing) * index;

			child.x = child_x;
			child.y = child_y;
			child.width = child_width;

			// For DeepinWorkspaceThumbClone, its height will be allocate by iteself
			if (child is DeepinWorkspaceAddButton) {
				child.height = child_height;
			}
		}

		/**
		 * Make pluse button visible if workspace number less than MAX_WORKSPACE_NUM.
		 */
		void setup_pluse_button ()
		{
			if (Prefs.get_num_workspaces () >= WindowManagerGala.MAX_WORKSPACE_NUM) {
				if (contains (add_button)) {
					remove_child (add_button);
				}
			} else {
				if (!contains (add_button)) {
					place_child (add_button, get_n_children ());
					insert_child_at_index (add_button, get_n_children ());
				}
			}
		}
	}
}
