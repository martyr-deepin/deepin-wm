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

		public Screen screen { get; construct; }

		public DeepinWorkspaceThumbCloneContainer (Screen screen)
		{
			Object (screen: screen);

			layout_manager = new BoxLayout ();
		}

		public void add_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			// Enable expand space in x and y axis so that all children will be
			// aligned even through in different size.
			workspace_clone.x_expand = true;
			workspace_clone.y_expand = true;

			var index = workspace_clone.workspace.index ();
			insert_child_at_index (workspace_clone, index);

			update_layout ();
		}

		public void remove_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			remove_child (workspace_clone);
		}

		public void update_layout ()
		{
			var display = screen.get_display ();
			var monitor_geom = screen.get_monitor_geometry (screen.get_primary_monitor ());

			y = (int) (monitor_geom.height * DeepinMultitaskingView.HORIZONTAL_OFFSET_PERCENT);

			var layout = layout_manager as BoxLayout;
			layout.spacing = (int) (monitor_geom.width * SPACING_PERCENT);

			foreach (var child in get_children ()) {
				child.width = monitor_geom.width * WORKSPACE_WIDTH_PERCENT;
			}
		}
	}
}
