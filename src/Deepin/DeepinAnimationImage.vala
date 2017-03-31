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
using Meta;
using Cairo;

namespace Gala
{
	/**
	 * Rendering background to actor through css styles.
	 */
	public class DeepinAnimationImage : Actor
	{
		//public string style_class { get; construct; }
        public int duration {get; set; default = 210; }  // in ms, 7 frames total
        public string[] frame_names {get; construct; }
        public string frame_hold {get; construct; }

        protected Gee.ArrayList<Surface> frames;
        protected Surface press_down_frame;
        protected int current_frame = -1;
        protected bool press_down = false;

        public signal void pressed ();
        public signal void activated ();
        public signal void deactivated ();

		public DeepinAnimationImage (string[] frames, string hold)
		{
			Object (frame_names: frames, frame_hold: hold);
		}

		construct
		{
			var canvas = new Canvas ();
			canvas.draw.connect (on_draw_content);

            frames = new Gee.ArrayList<Surface> ();

            foreach(var name in frame_names) {
                Gdk.Pixbuf? pixbuf;
                try {
                    pixbuf = new Gdk.Pixbuf.from_file (Config.PKGDATADIR + "/" + name);
                } catch (Error e) {
                    warning (e.message);
                }

                if (pixbuf != null) {
                    var surface = Gdk.cairo_surface_create_from_pixbuf (pixbuf, 1, null);
                    frames.add (surface);
                }
            }

            {
                Gdk.Pixbuf? pixbuf;
                try {
                    pixbuf = new Gdk.Pixbuf.from_file (Config.PKGDATADIR + "/" + frame_hold);
                } catch (Error e) {
                    warning (e.message);
                }

                if (pixbuf != null) {
                    press_down_frame = Gdk.cairo_surface_create_from_pixbuf (pixbuf, 1, null);
                }
            }

			content = canvas;
			notify["allocation"].connect (() => canvas.set_size ((int)width, (int)height));
		}

        uint animation_id = 0;
        void start_animation ()
        {
            stop_animation ();
            animation_id = Timeout.add(duration / frames.size, () => {
                content.invalidate ();
                current_frame++;
                Meta.verbose (@"current_frame = $current_frame, frames = $(frames.size)\n");
                if (current_frame == frames.size) {
                    animation_id = 0;
                    return false;
                }
                return true;
            });
        }

        void stop_animation ()
        {
            if (animation_id != 0) {
                Source.remove (animation_id);
                animation_id = 0;
            }
            current_frame = -1;
            content.invalidate ();
        }

		public void activate ()
		{
            if (visible == false) {
                visible = true;
                activated ();
                start_animation ();
            }
        }

		public void deactivate ()
        {
            if (visible == true) {
                visible = false;
                press_down = false;
                deactivated ();
                stop_animation ();
            }
        }

		protected virtual bool on_draw_content (Cairo.Context cr, int width, int height)
		{
            if (current_frame >= 0 && current_frame < frames.size) {
                cr.set_operator (Cairo.Operator.SOURCE);
                cr.set_source_surface (frames[current_frame], 0, 0);
                cr.paint ();
            } else if (press_down) {
                cr.set_operator (Cairo.Operator.SOURCE);
                cr.set_source_surface (press_down_frame, 0, 0);
                cr.paint ();
            } else {
                Clutter.cairo_clear (cr);
            }
			return false;
		}

		public override void get_preferred_width (float for_height,
												  out float min_width_p, out float nat_width_p)
		{
			nat_width_p = 38;
			min_width_p = 38;
		}

		public override void get_preferred_height (float for_width,
												   out float min_height_p, out float nat_height_p)
		{
			nat_height_p = 38;
			min_height_p = 38;
		}

		public override bool button_press_event (Clutter.ButtonEvent event)
        {
            press_down = true;
            content.invalidate ();
            return true;
        }

		public override bool button_release_event (Clutter.ButtonEvent event)
        {
            press_down = false;
            pressed ();
            return true;
        }
	}
}

