//
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

namespace Gala
{
	public class Background : Object
	{
		const double ANIMATION_OPACITY_STEP_INCREMENT = 4.0;
		const double ANIMATION_MIN_WAKEUP_INTERVAL = 1.0;

		public signal void loaded ();
		public signal void destroyed ();

		public Meta.Screen screen { get; construct; }
		public int workspace_index { get; construct; }
		public weak BackgroundSource background_source { get; construct; }
		public bool is_loaded { get; private set; default = false; }
		public GDesktop.BackgroundStyle style { get; construct; }
		public string? filename { get; construct; }
		public Meta.Background background { get; private set; }

		Animation? animation = null;
		Cancellable cancellable;
		uint update_animation_timeout_id = 0;
        ulong handler = 0;

		public Background (Meta.Screen screen, int workspace_index,
						   string? filename, BackgroundSource background_source,
						   GDesktop.BackgroundStyle style)
		{
			Object (screen: screen,
					workspace_index: workspace_index,
					background_source: background_source,
					style: style,
					filename: filename);
		}

		construct
		{
			background = new Meta.Background (screen);

			cancellable = new Cancellable ();

            int load_count = 0;
            handler = background.changed.connect (() => {
                set_loaded ();
            });

			load ();
		}

		public void destroy ()
		{
            Meta.verbose ("%s\n", Log.METHOD);

			cancellable.cancel ();

            SignalHandler.disconnect (background, handler);
            handler = 0;
		}

		void set_loaded ()
		{
            Meta.verbose ("%s\n", Log.METHOD);
			if (is_loaded)
				return;

            is_loaded = true;
            Idle.add (() => {
				loaded ();
				return false;
			});
		}

		void load_pattern ()
		{
			string color_string;
			var settings = background_source.settings;

			color_string = settings.get_string ("primary-color");
			var color = Clutter.Color.from_string (color_string);

			color_string = settings.get_string("secondary-color");
			var second_color = Clutter.Color.from_string (color_string);

			var shading_type = settings.get_enum ("color-shading-type");

			if (shading_type == GDesktop.BackgroundShading.SOLID)
				background.set_color (color);
			else
				background.set_gradient ((GDesktop.BackgroundShading) shading_type, color, second_color);
		}

		void watch_file (string filename)
		{
			var cache = BackgroundCache.get_default ();
			cache.monitor_file (filename);
		}

		void load_image (string filename)
        {
            var cache = Meta.BackgroundImageCache.get_default ();

#if HAS_MUTTER316
            background.set_file (File.new_for_path (filename), style);
#else
            background.set_filename (filename, style);
#endif

            watch_file (filename);
        }

		void load ()
		{
			load_pattern ();

			if (filename == null)
				set_loaded ();
			else
				load_image (filename);
		}
	}
}
