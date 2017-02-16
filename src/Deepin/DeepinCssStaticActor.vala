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
	 * Rendering background to actor through css styles.
	 */
	public class DeepinCssStaticActor : Actor
	{
		public string style_class { get; construct; }
		public Gtk.StateFlags state { get; construct; }

		protected Gtk.StyleContext? style_context;

		public DeepinCssStaticActor (
			string style_class, Gtk.StateFlags state = Gtk.StateFlags.NORMAL)
		{
			Object (style_class: style_class, state: state);
		}

		construct
		{
			if (style_context == null) {
				style_context = DeepinUtils.new_css_style_context (style_class);
			}

			var canvas = new Canvas ();
			canvas.draw.connect (on_draw_content);

			content = canvas;
			notify["allocation"].connect (() => canvas.set_size ((int)width, (int)height));
		}

		protected virtual bool on_draw_content (Cairo.Context cr, int width, int height)
		{
			// clear the content
			cr.set_operator (Cairo.Operator.CLEAR);
			cr.paint ();
			cr.set_operator (Cairo.Operator.OVER);

			style_context.set_state (state);
			style_context.render_background (cr, 0, 0, width, height);
			style_context.render_frame (cr, 0, 0, width, height);

			return false;
		}
	}
}
