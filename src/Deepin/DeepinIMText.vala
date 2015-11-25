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
using Gtk;
using Gdk;
using Meta;

namespace Gala
{
	/**
	 * Show workspace name after workspace switched.
	 */
	public class DeepinIMText: Clutter.Text
	{
        Gtk.IMContext imctx;
        Gdk.Window? event_window;
        Meta.Window? target;
        Clutter.Clone? im_clone;
        bool has_preedit_str;

        public Meta.Screen screen { get; construct; }

		public DeepinIMText (Meta.Screen screen)
		{
			Object (screen: screen);
        }

        void on_window_created (Meta.Window window)
        {
            Meta.verbose ("%s\n", Log.METHOD);
            if (im_clone != null) return;

            if (window.wm_class != null && 
                    window.wm_class.index_of ("qimpanel") >= 0) {
                Meta.verbose ("%s: find qimpanel\n", Log.METHOD);
                target = window;
               
                Idle.add (on_idle_raise_impanel);
            } 
        }

        bool on_idle_raise_impanel ()
        {
            if (im_clone != null) return false;

            var actor = target.get_compositor_private () as WindowActor; 
            im_clone = new Clutter.Clone (actor);

            ulong handler = 0;
            handler = actor.destroy.connect (() => {
                if (im_clone != null) {
                    im_clone.destroy ();
                    im_clone = null;
                }
                SignalHandler.disconnect (target, handler);
            });

            actor.show.connect (() => {
                if (has_key_focus ()) im_clone.show (); 
            });
            actor.hide.connect (() => {
                im_clone.hide (); 
            });

            var top_window_group = Compositor.get_top_window_group_for_screen (screen);
            var ui_group = top_window_group.get_parent ();

            ui_group.insert_child_above (im_clone, null);
            if (has_key_focus ()) {
                im_clone.visible = actor.visible;
            } else {
                im_clone.hide ();
            }

            float ax, ay;
            get_transformed_position (out ax, out ay);
            im_clone.set_position (ax, ay + height);

            return false;
        }

        void on_ctx_commit (string str)
        {
            Meta.verbose ("%s: %s\n", Log.METHOD, str);
            delete_selection ();
            insert_text (str, get_cursor_position ());
        }
        
        void on_preedit_changed ()
        {
            string preedit_str;
            Pango.AttrList preedit_attrs;
            uint cursor_pos;
            delete_selection ();

            imctx.get_preedit_string (out preedit_str,
                    out preedit_attrs, out cursor_pos);
            has_preedit_str = preedit_str != null && preedit_str.length > 0;
            
            set_preedit_string (preedit_str, preedit_attrs, cursor_pos);
            //Meta.verbose ("%s: preedit_str = %s\n", Log.METHOD, preedit_str);
        }

        bool on_delete_surrounding (int offset, int n_chars)
        {
            Meta.verbose ("%s\n", Log.METHOD);
            if (this.editable) {
                var cursor_pos = get_cursor_position();
                delete_text (cursor_pos + offset,
                        cursor_pos + offset + n_chars);
            }

            return true;
        }
        
        bool on_retrieve_surrounding ()
        {
            Meta.verbose ("%s\n", Log.METHOD);
            var buffer = get_buffer ();
            var text = buffer.get_text ();

            var cursor_pos = get_cursor_position ();
            if (cursor_pos < 0)
                cursor_pos = (int) buffer.get_length ();

            imctx.set_surrounding (text,
                    /* length and cursor_index are in bytes */
                    (int) buffer.get_bytes (),
                    text.index_of_nth_char (cursor_pos));

            return true;
        }

		construct
		{
			var display = screen.get_display ();
            display.window_created.connect (on_window_created);

            imctx = new Gtk.IMMulticontext ();
            imctx.commit.connect(on_ctx_commit);

            imctx.retrieve_surrounding.connect (on_retrieve_surrounding);
            imctx.delete_surrounding.connect (on_delete_surrounding);
            imctx.preedit_changed.connect (on_preedit_changed);
		}

		~DeepinIMText ()
		{
			var display = screen.get_display ();
            display.window_created.disconnect (on_window_created);
		}

        uint is_modifier (uint keyval)
        {
            switch (keyval) {
                case Gdk.Key.Shift_L:
                case Gdk.Key.Shift_R:
                case Gdk.Key.Control_L:
                case Gdk.Key.Control_R:
                case Gdk.Key.Caps_Lock:
                case Gdk.Key.Shift_Lock:
                case Gdk.Key.Meta_L:
                case Gdk.Key.Meta_R:
                case Gdk.Key.Alt_L:
                case Gdk.Key.Alt_R:
                case Gdk.Key.Super_L:
                case Gdk.Key.Super_R:
                case Gdk.Key.Hyper_L:
                case Gdk.Key.Hyper_R:
                case Gdk.Key.ISO_Lock:
                case Gdk.Key.ISO_Level2_Latch:
                case Gdk.Key.ISO_Level3_Shift:
                case Gdk.Key.ISO_Level3_Latch:
                case Gdk.Key.ISO_Level3_Lock:
                case Gdk.Key.ISO_Level5_Shift:
                case Gdk.Key.ISO_Level5_Latch:
                case Gdk.Key.ISO_Level5_Lock:
                case Gdk.Key.ISO_Group_Shift:
                case Gdk.Key.ISO_Group_Latch:
                case Gdk.Key.ISO_Group_Lock:
                    return 1;
                default: return 0;
            }
        }

        Gdk.Event to_gdk_event (Clutter.KeyEvent ev)
        {
            var gdkev = new Gdk.Event (
                    ev.type == Clutter.EventType.KEY_PRESS? 
                    Gdk.EventType.KEY_PRESS : Gdk.EventType.KEY_RELEASE);

            event_window.ref ();
            gdkev.key.window = event_window;
            gdkev.key.send_event = 0;
            gdkev.key.time = ev.time;
            gdkev.key.state = (Gdk.ModifierType)ev.modifier_state;
            gdkev.key.keyval = ev.keyval;
            gdkev.key.hardware_keycode = ev.hardware_keycode;
            gdkev.key.length = 0;
            gdkev.key.str = null;
            gdkev.key.is_modifier = is_modifier (gdkev.key.keyval);

            return gdkev;
        }

        public override bool captured_event (Clutter.Event event)
        {
            var type = event.get_type ();
            if (type != Clutter.EventType.KEY_PRESS &&
                    type != Clutter.EventType.KEY_RELEASE)
                return false;

            if (this.editable) {
                Meta.verbose ("%s\n", Log.METHOD);
                var kev = event.key;

                var gdkev = to_gdk_event (kev);
                if (imctx.filter_keypress (gdkev.key)) {
                    return true;
                }

                if (type == Clutter.EventType.KEY_PRESS && 
                        kev.keyval == Clutter.Key.Return) {
                    imctx.reset ();
                }
            }
            return false;
        }

        public override bool button_press_event (Clutter.ButtonEvent event)
        {
            Meta.verbose ("imtext: %s\n", Log.METHOD);
            imctx.reset ();
            return base.button_press_event (event);
        }

		public override void key_focus_in ()
		{
            Meta.verbose ("imtext: %s\n", Log.METHOD);
            if (editable) {
                imctx.focus_in ();
            }
            base.key_focus_in ();
		}

		public override void key_focus_out ()
		{
            Meta.verbose ("imtext: %s\n", Log.METHOD);
            if (editable) {
                if (im_clone != null) im_clone.hide ();
                imctx.focus_out ();
            }
            base.key_focus_out ();
		}

		public override void realize ()
		{
            if (event_window == null) {
                var attrs = Gdk.WindowAttr () {
                    window_type = Gdk.WindowType.TOPLEVEL,
                    event_mask = (Gdk.EventMask.BUTTON_PRESS_MASK |
                            Gdk.EventMask.BUTTON_RELEASE_MASK |
                            Gdk.EventMask.ENTER_NOTIFY_MASK |
                            Gdk.EventMask.KEY_PRESS_MASK |
                            Gdk.EventMask.KEY_RELEASE_MASK |
                            Gdk.EventMask.LEAVE_NOTIFY_MASK),
                    wclass = WindowWindowClass.INPUT_ONLY,
                    x = (int)x,
                    y = (int)y,
                    width = (int)width,
                    height = (int)height
                };
                    

                var attributes_mask = WindowAttributesType.X |
                    WindowAttributesType.Y;
                event_window = new Gdk.Window (null, attrs, attributes_mask);
                imctx.set_client_window (event_window);
            }
		}

		public override void unrealize ()
		{
            if (event_window != null) {
                imctx.reset ();
                imctx.set_client_window (null);
                event_window.destroy ();
                event_window = null;
            }

		}
	}
}

