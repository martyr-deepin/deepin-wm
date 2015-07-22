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
	 * Will be put at end of workspace thumbnail list in DeepinMultitaskingView if number less than
	 * MAX_WORKSPACE_NUM.
	 */
	public class DeepinWorkspaceAddButton : DeepinCssStaticActor
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
}
