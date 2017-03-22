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
        public int duration {get; set; default = 240; }  // in ms, 6 frames total
        public string[] frame_names {get; construct; }
        protected Gee.ArrayList<Surface> frames;
        protected int current_frame = 0;

        uint animation_id = 0;
        bool reverse_animation = false;
        bool activated = false;

        public signal void pressed ();

		public DeepinAnimationImage (string[] frames)
		{
			Object (frame_names: frames);
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

			content = canvas;
			notify["allocation"].connect (() => canvas.set_size ((int)width, (int)height));
		}

        void start_animation ()
        {
            stop_animation ();
            animation_id = Timeout.add(duration / frames.size, () => {
                content.invalidate ();
                if (reverse_animation) {
                    current_frame--;
                    stderr.printf (@"reverse current_frame = $current_frame, frames = $(frames.size)\n");
                    if (current_frame < 0) {
                        visible = false;
                        animation_id = 0;
                        return false;
                    }
                } else {
                    current_frame++;
                    Meta.verbose (@"current_frame = $current_frame, frames = $(frames.size)\n");
                    stderr.printf (@"current_frame = $current_frame, frames = $(frames.size)\n");
                    if (current_frame == frames.size - 1) {
                        animation_id = 0;
                        return false;
                    }
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
            if (reverse_animation) {
                current_frame = frames.size - 1;
            } else {
                current_frame = -1;
            }
        }

		public void activate ()
		{
            if (activated == false) {
                activated = true;
                visible = true;
                reverse_animation = false;
                start_animation ();
            }
        }

		public void deactivate ()
        {
            if (activated == true) {
                activated = false;
                reverse_animation = true;
                start_animation ();
            }
        }

		protected virtual bool on_draw_content (Cairo.Context cr, int width, int height)
		{
            if (current_frame >= 0 && current_frame < frames.size) {
                cr.set_operator (Cairo.Operator.SOURCE);
                cr.set_source_surface (frames[current_frame], 0, 0);
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

		public override bool button_release_event (Clutter.ButtonEvent event)
        {
            pressed ();
            return true;
        }
	}
}

