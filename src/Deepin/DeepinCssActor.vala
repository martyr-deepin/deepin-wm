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

namespace Gala
{
	/**
	 * Rendering background with animation support to actor through css styles.
	 */
	public class DeepinCssActor : Actor
	{
		public string style_class { get; construct; }

		protected AnimationMode progress_mode = AnimationMode.EASE_IN_OUT_QUAD;

		Gdk.RGBA? bg_color_normal = null;
		Gdk.RGBA? bg_color_selected = null;
		int? border_radius = null;

		Gdk.RGBA _bg_color;
		Gdk.RGBA bg_color {
			get { return _bg_color; }
			set {
				_bg_color = value;
				content.invalidate ();
			}
		}

		Gdk.RGBA _bg_color_from;
		Gdk.RGBA _bg_color_to;

		Timeline? timeline = null;

		bool _select = false;
		public bool select {
			get { return _select; }
			set {
				if (_select == value) {
					return;
				}

				_select = value;

				if (timeline != null && timeline.is_playing ()) {
					timeline.stop ();
				}
				if (get_easing_duration () > 0) {
					timeline = new Timeline (get_easing_duration ());
					timeline.progress_mode = get_easing_mode ();
					timeline.new_frame.connect (on_new_frame);

					if (value) {
						_bg_color_from = bg_color;
						_bg_color_to = bg_color_selected;
					} else {
						_bg_color_from = bg_color;
						_bg_color_to = bg_color_normal;
					}
					timeline.start ();
				} else {
					bg_color = _select ? bg_color_selected : bg_color_normal;
				}
			}
		}

		public DeepinCssActor (string style_class)
		{
			Object (style_class: style_class);
		}

		construct
		{
			bg_color_normal = DeepinUtils.get_css_background_color_gdk_rgba (style_class);
			bg_color_selected = DeepinUtils.get_css_background_color_gdk_rgba (
				style_class, Gtk.StateFlags.SELECTED);
			border_radius = DeepinUtils.get_css_border_radius (style_class, Gtk.StateFlags.SELECTED);

			var canvas = new Canvas ();
			canvas.draw.connect (on_draw_content);

			content = canvas;
			notify["allocation"].connect (() => canvas.set_size ((int)width, (int)height));

			bg_color = bg_color_normal;
		}

		~DeepinCssActor ()
		{
			if (timeline != null) {
				timeline.new_frame.disconnect (on_new_frame);
				if (timeline.is_playing ()) {
					timeline.stop ();
				}
			}
		}

		bool on_draw_content (Cairo.Context cr, int width, int height)
		{
			// clear the content
			cr.set_operator (Cairo.Operator.CLEAR);
			cr.paint ();
			cr.set_operator (Cairo.Operator.OVER);

			cr.set_source_rgba (bg_color.red, bg_color.green, bg_color.blue, bg_color.alpha);
			Granite.Drawing.Utilities.cairo_rounded_rectangle (
				cr, 0, 0, (int)width, (int)height, border_radius);
			cr.fill ();

			return false;
		}

		void on_new_frame (int msecs)
		{
			double progress = timeline.get_progress ();
			Gdk.RGBA from_color = _bg_color_from;
			Gdk.RGBA to_color = _bg_color_to;
			double red, green, blue, alpha;
			red = from_color.red + (to_color.red - from_color.red) * progress;
			green = from_color.green + (to_color.green - from_color.green) * progress;
			blue = from_color.blue + (to_color.blue - from_color.blue) * progress;
			alpha = from_color.alpha + (to_color.alpha - from_color.alpha) * progress;
			bg_color = { red, green, blue, alpha };
		}
	}
}
