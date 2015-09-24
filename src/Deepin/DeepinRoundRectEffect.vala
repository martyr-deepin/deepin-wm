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
		public int radius { get; construct; }

		public Gdk.RGBA color { get; construct set; }

		Cogl.Material material;
		Cogl.Texture texture;

		// TODO: cache
		// static Gee.HashMap<string,Shadow> shadow_cache;

		public DeepinRoundRectOutlineEffect (int radius, Gdk.RGBA color)
		{
			Object (radius: radius, color: color);
		}

		construct
		{
			material = new Cogl.Material ();
		}

		public void update_color (Gdk.RGBA new_color)
		{
			if (color != new_color) {
				color = new_color;
				if (texture != null) {
					uint width = texture.get_width ();
					uint height = texture.get_height ();
					texture = null;
					update_texture (width, height);
				}
			}
		}

		void update_texture (uint width, uint height)
		{
			if (texture != null && texture.get_width () == width &&
				texture.get_height () == height) {
				return;
			}

			// draw pattern through cairo
			var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, (int)width, (int)height);
			var cr = new Cairo.Context (surface);

			cr.set_line_width (1);
			cr.set_line_cap (Cairo.LineCap.ROUND);

			cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
			cr.set_antialias (Cairo.Antialias.BEST);

			Granite.Drawing.Utilities.cairo_rounded_rectangle (cr, 0, 0, width, height, radius);
			cr.stroke ();

			// convert cairo surface to cogl material
			texture = new Cogl.Texture.from_data (width, height, 0,
												  Cogl.PixelFormat.BGRA_8888_PRE,
												  Cogl.PixelFormat.ANY, surface.get_stride (),
												  surface.get_data ());

			material.set_layer (0, texture);
		}

		public override void paint (EffectPaintFlags flags)
		{
			actor.continue_paint ();

			update_texture ((uint)actor.width, (uint)actor.height);

			Cogl.set_source (material);
			Cogl.rectangle (0, 0, actor.width, actor.height);
		}
	}
}
