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

namespace Gala
{
	public class ShadowEffect : Effect
	{
		private class Shadow : Object
		{
			public int users { get; set; default = 1; }
			public Cogl.Texture texture { get; construct; }

			public Shadow (Cogl.Texture texture)
			{
				Object (texture: texture);
			}
		}

		// the sizes of the textures often repeat, especially for the background actor
		// so we keep a cache to avoid creating the same texture all over again.
		static Gee.HashMap<string,Shadow> shadow_cache;

		static construct
		{
			shadow_cache = new Gee.HashMap<string,Shadow> ();
		}

		public int shadow_size { get; construct; }
		public int shadow_spread { get; construct; }

		public float scale_factor { get; set; default = 1; }
		public uint8 shadow_opacity { get; set; default = 255; }
		public int shadow_yoffset { get; construct; }
        public bool do_clip_shadow {get; set; default = true; }
        public bool high_blur_effect {get; set; default = true; }

		Cogl.Material material;
		string? current_key = null;

		public ShadowEffect (int actor_width, int actor_height, int shadow_size, int shadow_spread,
							 uint8 shadow_opacity = 255, int yoffset = -1,
                             bool high_blur_effect = true, bool do_clip_shadow = true)
		{
            if (yoffset < 0) { yoffset = shadow_spread; }

			Object (shadow_size: shadow_size, shadow_spread: shadow_spread,
					shadow_opacity: shadow_opacity, shadow_yoffset: yoffset, 
                    high_blur_effect: high_blur_effect, do_clip_shadow: do_clip_shadow);

			material = new Cogl.Material ();

			update_size (actor_width, actor_height);
		}

		~ShadowEffect ()
		{
			if (current_key != null)
				decrement_shadow_users (current_key);
		}

		public void update_size (int actor_width, int actor_height)
		{
			var shadow = get_shadow (actor_width, actor_height, shadow_size, shadow_spread);
			material.set_layer (0, shadow);
		}

		Cogl.Texture get_shadow (int actor_width, int actor_height, int shadow_size, int shadow_spread)
		{
			if (current_key != null) {
				decrement_shadow_users (current_key);
			}

			Shadow? shadow = null;

			var width = actor_width + shadow_size * 2;
			var height = actor_height + shadow_size * 2;

			current_key = "%ix%i:%i:%i".printf (width, height, shadow_size, shadow_spread);
			if ((shadow = shadow_cache.@get (current_key)) != null) {
				shadow.users++;
				return shadow.texture;
			}

			// fill a new texture for this size
			var buffer = new Granite.Drawing.BufferSurface (width, height);
            Granite.Drawing.Utilities.cairo_rounded_rectangle (buffer.context, 
                    shadow_size - shadow_spread - 2, shadow_size - shadow_spread + shadow_yoffset,
                    actor_width + shadow_spread * 2 + 4, actor_height + shadow_spread * 2, 
                    6);
            buffer.context.set_source_rgba (0, 0, 0, 1.0);
			buffer.context.fill ();

            if (high_blur_effect)
                buffer.gaussian_blur (shadow_size / 2 + 2);
            else 
                buffer.exponential_blur (shadow_size / 2 + 2);

			var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
			var cr = new Cairo.Context (surface);

            Cairo.RectangleInt r1 = {0, 0, width, height};
            Cairo.RectangleInt r2 = {shadow_size, shadow_size - shadow_yoffset, actor_width, actor_height};

            if (do_clip_shadow) {
                cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                cr.new_path ();
                //FIXME: should pass radius from parent
                DeepinUtils.draw_round_box (cr, r2.width, r2.height, 5, r2.x, r2.y);

                cr.new_sub_path ();
                cr.move_to (r1.width, 0);
                cr.line_to (0, 0);
                cr.line_to (0, r1.height);
                cr.line_to (r1.width, r1.height);
                cr.close_path ();

                cr.clip ();
            }
            cr.rectangle (r1.x, r1.y, r1.width, r1.height);
            cr.set_source_surface (buffer.surface, 0, 0);
			cr.fill ();

			var texture = new Cogl.Texture.from_data (width, height, 0, Cogl.PixelFormat.BGRA_8888_PRE,
				Cogl.PixelFormat.ANY, surface.get_stride (), surface.get_data ());

			shadow_cache.@set (current_key, new Shadow (texture));

			return texture;
		}

		void decrement_shadow_users (string key)
		{
			var shadow = shadow_cache.@get (key);

			if (shadow == null)
				return;

			if (--shadow.users == 0) {
				shadow_cache.unset (key);
            }
		}

		public override void paint (EffectPaintFlags flags)
		{
			var size = shadow_size * scale_factor;

			var opacity = actor.get_paint_opacity () * shadow_opacity / 255;
			var alpha = Cogl.Color.from_4ub (255, 255, 255, opacity);
			alpha.premultiply ();

			material.set_color (alpha);

			Cogl.set_source (material);
            Cogl.rectangle (-size, -size + shadow_yoffset,
                    actor.width + size, actor.height + size + shadow_yoffset);

			actor.continue_paint ();
		}
	}
}
