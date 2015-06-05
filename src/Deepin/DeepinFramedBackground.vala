//
//  Copyright (C) 2014 Xu Fasheng, Deepin, Inc.
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
	 * Utility class which adds a border and a shadow to a Background
	 */
#if HAS_MUTTER314
	class DeepinFramedBackground : BackgroundManager
#else
	class DeepinFramedBackground : Background
#endif
	{
		public bool enable_shadow { get; construct; }

		public DeepinFramedBackground (Screen screen, bool enable_shadow = true)
		{
#if HAS_MUTTER314
			Object (screen: screen, enable_shadow: enable_shadow, monitor_index: screen.get_primary_monitor (), control_position: false);
#else
			Object (screen: screen, enable_shadow: enable_shadow, monitor: screen.get_primary_monitor (),
					settings: BackgroundSettings.get_default ().schema);
#endif
		}

		construct
		{
			var primary = screen.get_primary_monitor ();
			var monitor_geom = screen.get_monitor_geometry (primary);

			if (enable_shadow) {
				add_effect (new ShadowEffect (monitor_geom.width, monitor_geom.height, 40, 5));
			}
		}

		public override void paint ()
		{
			base.paint ();

			// draw outer rectangle only when shadow effect enabled
			if (enable_shadow) {
				Cogl.set_source_color4ub (0, 0, 0, 100);
				Cogl.Path.rectangle (0, 0, width, height);
				Cogl.Path.stroke ();

				Cogl.set_source_color4ub (255, 255, 255, 25);
				Cogl.Path.rectangle (0.5f, 0.5f, width - 1, height - 1);
				Cogl.Path.stroke ();
			}
		}
	}
}
