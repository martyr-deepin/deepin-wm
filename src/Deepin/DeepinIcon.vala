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
	public class DeepinIconActor : Actor
	{
		public string icon_name { get; construct; }
        public signal void pressed ();
        public signal void released ();

        const int BASE_SIZE = 48;
        double scale_factor = 1.0;

        public enum IconState {
            Normal, 
            Prelight,
            Pressed,
        }

        IconState _state = IconState.Normal;
		public IconState state {
			get { return _state; }
			set {
				if (_state == value) {
					return;
				}

				_state = value;
                update_state ();
			}
		}

        GtkClutter.Texture normal_icon;
        GtkClutter.Texture hover_icon;
        GtkClutter.Texture pressed_icon;

		public DeepinIconActor (string name)
		{
			Object (icon_name: name);
		}

		construct
		{
            normal_icon = create_button (IconState.Normal);
            hover_icon = create_button (IconState.Prelight);
            pressed_icon = create_button (IconState.Pressed);

            scale_factor = DeepinXSettings.get_default ().schema.get_double ("scale-factor"); 
			DeepinXSettings.get_default ().schema.changed.connect (on_scale_changed);
            on_scale_changed ();

            hover_icon.visible = false;
            pressed_icon.visible = false;

            add_child (hover_icon);
            add_child (pressed_icon);
            add_child (normal_icon);

			reactive = true;
            state = IconState.Normal;
		}

		private void on_scale_changed() 
        {
            scale_factor = DeepinXSettings.get_default ().scale_factor; 
            int real_size = (int)(BASE_SIZE * scale_factor);

            normal_icon.set_scale (scale_factor / 2.0, scale_factor / 2.0);
            hover_icon.set_scale (scale_factor / 2.0, scale_factor / 2.0);
            pressed_icon.set_scale (scale_factor / 2.0, scale_factor / 2.0);
            set_size (real_size, real_size);
        }

		~DeepinIconActor ()
		{
		}

		public override void get_preferred_width (float for_height,
												  out float min_width_p, out float nat_width_p)
		{
			nat_width_p = (int)(BASE_SIZE * scale_factor);
			min_width_p = (int)(BASE_SIZE * scale_factor);
		}

		public override void get_preferred_height (float for_width,
												   out float min_height_p, out float nat_height_p)
		{
			nat_height_p = (int)(BASE_SIZE * scale_factor);
			min_height_p = (int)(BASE_SIZE * scale_factor);
		}

		public override bool enter_event (Clutter.CrossingEvent event)
		{
            state = IconState.Prelight; 
            return false;
        }

		public override bool leave_event (Clutter.CrossingEvent event)
        {
            state = IconState.Normal; 
            return false;
        }

		public override bool button_press_event (Clutter.ButtonEvent event)
        {
            state = IconState.Pressed;
            pressed ();
            return true;
        }

		public override bool button_release_event (Clutter.ButtonEvent event)
        {
            state = IconState.Prelight;
            released ();
            return true;
        }

        void update_state ()
        {
            normal_icon.visible = _state == IconState.Normal;
            hover_icon.visible = _state == IconState.Prelight;
            pressed_icon.visible = _state == IconState.Pressed;
        }

		Gdk.Pixbuf? get_button_pixbuf (IconState state)
        {
            Gdk.Pixbuf? pixbuf;
            var size = (int)(BASE_SIZE * 2);

            var st_name = state == IconState.Normal ? "_normal" : state == IconState.Prelight ? "_hover" : "_press";
            try {
                pixbuf = new Gdk.Pixbuf.from_file_at_scale (
                        Config.PKGDATADIR + "/" + icon_name + st_name + ".svg",
                        size, size, true);
            } catch (Error e) {
                warning (e.message);
                return null;
            }

            return pixbuf;
        }

		GtkClutter.Texture create_button (IconState state)
		{
			var texture = new GtkClutter.Texture ();
			var pixbuf = get_button_pixbuf (state);


			if (pixbuf != null) {
				try {
					texture.set_from_pixbuf (pixbuf);
				} catch (Error e) {}
			} else {
				// we'll just make this red so there's at least something as an
				// indicator that loading failed. Should never happen and this
				// works as good as some weird fallback-image-failed-to-load pixbuf
				texture.background_color = { 255, 0, 0, 255 };
			}

			return texture;
		}
	}
}

