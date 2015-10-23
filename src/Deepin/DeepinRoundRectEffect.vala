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

namespace Gala
{
	// Clip rounded rectangle through Cogl.Path with smoothness issue.
	public class DeepinRoundRectEffect : Effect
	{
		public int radius { get; construct; }

		public DeepinRoundRectEffect (int radius)
		{
			Object (radius: radius);
		}

		public override void paint (EffectPaintFlags flags)
		{
			Cogl.Path.round_rectangle (0, 0, actor.width, actor.height, radius, 1);
			Cogl.clip_push_from_path ();
			actor.continue_paint ();
			Cogl.clip_pop ();
		}
	}

	// Draw rouned rectangle outline to make DeepinRoundRectEffect looks antialise.
	class DeepinRoundRectOutlineEffect : Effect
	{
		private class RoundRect : Object
		{
			public int users { get; set; default = 1; }
			public Cogl.Texture texture { get; construct; }
			public RoundRect (Cogl.Texture texture)
			{
				Object (texture: texture);
			}
		}

		static Gee.HashMap<string,RoundRect> rect_cache;

		public int width { get; set; }
		public int height { get; set; }
		public int radius { get; set; }
		public Gdk.RGBA color { get; set; }

		Cogl.Material material;
		string? current_key = null;

		public DeepinRoundRectOutlineEffect (int width, int height, int radius, Gdk.RGBA color)
		{
			Object (width: width, height: height, radius: radius, color: color);
		}

		static construct
		{
			rect_cache = new Gee.HashMap<string,RoundRect> ();
		}

		construct
		{
			material = new Cogl.Material ();
			update_size (width, height);
		}

		~DeepinRoundRectOutlineEffect ()
		{
			if (current_key != null) {
				decrement_rect_users (current_key);
			}
		}

		void decrement_rect_users (string key)
		{
			var rect = rect_cache.@get (key);
			if (rect == null) {
				return;
			}
			if (--rect.users == 0) {
				rect_cache.unset (key);
			}
		}

		public void update_color (Gdk.RGBA new_color)
		{
			if (color != new_color) {
				color = new_color;
				var texture = get_texture (width, height, radius, color);
				material.set_layer (0, texture);
			}
		}

		void update_size (int new_width, int new_height)
		{
			if (width != new_width || height != new_height) {
				width = new_width;
				height = new_height;
				var texture = get_texture (width, height, radius, color);
				if (texture != null) {
					material.set_layer (0, texture);
				}
			}
		}

		Cogl.Texture? get_texture (int new_width, int new_height, int new_radius,
								  Gdk.RGBA new_color)
		{
			if (new_width == 0 || new_height == 0) {
				return null;
			}

			if (current_key != null) {
				decrement_rect_users (current_key);
			}

			RoundRect? rect = null;
			var current_key = "%dx%d:%i:%s".printf (new_width, new_height, new_radius,
												new_color.to_string ());
			rect = rect_cache.@get (current_key);
			if (rect != null) {
				rect.users++;
				return rect.texture;
			}

			// draw pattern through cairo
			var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, (int)new_width,
												  (int)new_height);
			var cr = new Cairo.Context (surface);

			cr.set_line_width (1);
			cr.set_line_cap (Cairo.LineCap.ROUND);

			cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
			cr.set_antialias (Cairo.Antialias.BEST);

			Granite.Drawing.Utilities.cairo_rounded_rectangle (cr, 0, 0, (uint)new_width,
															   (uint)new_height, radius);
			cr.stroke ();

			// convert cairo surface to cogl material
			var texture = new Cogl.Texture.from_data ((uint)new_width, (uint)new_height, 0,
													  Cogl.PixelFormat.BGRA_8888_PRE,
													  Cogl.PixelFormat.ANY, surface.get_stride (),
													  surface.get_data ());

			// fill a new rounded rectangle
			rect_cache.@set (current_key, new RoundRect (texture));

			return texture;
		}

		public override void paint (EffectPaintFlags flags)
		{
			actor.continue_paint ();

			int width = (int)Math.roundf (actor.width);
			int height = (int)Math.roundf (actor.height);
			update_size (width, height);

			Cogl.set_source (material);
			Cogl.rectangle (0, 0, width, height);
		}
	}
}
