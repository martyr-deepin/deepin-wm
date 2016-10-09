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
        Gdk.Window? event_window = null;
        Meta.Window? target = null;
        Clutter.Clone? im_clone = null;
        bool has_preedit_str = false;
        uint fcitx_watch_id = 0;

        public Meta.Screen screen { get; construct; }

		public DeepinIMText (Meta.Screen screen)
		{
			Object (screen: screen);
        }

        void on_window_created (Meta.Window window)
        {
            if (window.is_override_redirect () && 
                    window.wm_class != null && 
                    window.wm_class.index_of ("qimpanel") >= 0) {
                var outer_rect = window.get_frame_rect ();
                if (outer_rect.x < 0 && outer_rect.y < 0) {
                    return;
                }

                if (outer_rect.width <= 32 && outer_rect.height <= 32) {
                    return;
                }

                Meta.verbose ("%s: find qimpanel wid 0x%x\n", Log.METHOD, window.get_xwindow ());
                if (im_clone == null || target != window) {
                    if (im_clone != null) {
                        im_clone.destroy ();
                        im_clone = null;
                    }
                    target = window;
                    Idle.add (on_idle_raise_impanel);
                }
            } 
        }

        bool on_idle_raise_impanel ()
        {
            if (im_clone != null) return false;

            var actor = target.get_compositor_private () as WindowActor; 
            if (actor == null) {
                Meta.verbose ("target found, but actor is null\n");
                target = null;
                return false;
            }
            assert (actor != null);

            im_clone = new Clutter.Clone (actor);

            ulong handler = 0;
            handler = actor.destroy.connect (() => {
                if (im_clone != null) {
                    im_clone.destroy ();
                    im_clone = null;

                    target = null;
                }

                SignalHandler.disconnect (actor, handler);
                handler = 0;
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

            create_context ();
            scan_impanel ();

            fcitx_watch_id = GLib.Bus.watch_name (BusType.SESSION, "org.fcitx.Fcitx",
                    0, im_appeared, im_vanished);
        }

        void im_appeared (GLib.DBusConnection connection, string name, string name_owner)
        {
            Meta.verbose ("%s: name = %s, owner = %s\n", Log.METHOD, name, name_owner);

            if (imctx == null) {
                create_context ();
            }

            if (target == null) {
                scan_impanel ();
            }
        }

        void im_vanished (GLib.DBusConnection connection, string name)
        {
            Meta.verbose ("%s\n", Log.METHOD);
            if (imctx != null) {
                destroy_context ();
            }
        }

        void scan_impanel ()
        {
            if (target != null) return;

            unowned List<WindowActor> actors = Compositor.get_window_actors (screen);

            foreach (var actor in actors) {
                var window = actor.get_meta_window ();
                on_window_created (window);
            }
        }

        void destroy_context () {
            Meta.verbose ("%s\n", Log.METHOD);
            if (imctx != null) {
                imctx.commit.disconnect(on_ctx_commit);
                imctx.retrieve_surrounding.disconnect (on_retrieve_surrounding);
                imctx.delete_surrounding.disconnect (on_delete_surrounding);
                imctx.preedit_changed.disconnect (on_preedit_changed);

                imctx.set_client_window (null);
                imctx = null;
            }
        }

        void create_context () {
            Meta.verbose ("%s\n", Log.METHOD);
            if (imctx == null) {
                imctx = new Gtk.IMMulticontext ();
                imctx.commit.connect(on_ctx_commit);

                imctx.retrieve_surrounding.connect (on_retrieve_surrounding);
                imctx.delete_surrounding.connect (on_delete_surrounding);
                imctx.preedit_changed.connect (on_preedit_changed);

                if (event_window != null)
                    imctx.set_client_window (event_window);
            }
		}

		~DeepinIMText ()
		{
			var display = screen.get_display ();
            display.window_created.disconnect (on_window_created);
            GLib.Bus.unwatch_name (fcitx_watch_id);
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

        Gdk.Event? to_gdk_event (Clutter.Event ev)
        {
            if (event_window == null)
                return null;

            var gdkev = new Gdk.Event (
                    ev.type == Clutter.EventType.KEY_PRESS? 
                    Gdk.EventType.KEY_PRESS : Gdk.EventType.KEY_RELEASE);

            event_window.ref ();
            gdkev.key.window = event_window;
            gdkev.key.send_event = 0;
            gdkev.key.time = ev.get_time();
            gdkev.key.state = (Gdk.ModifierType)ev.key.modifier_state;
            gdkev.key.keyval = ev.key.keyval;
            gdkev.key.hardware_keycode = ev.key.hardware_keycode;
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
                var gdkev = to_gdk_event (event);
                if (gdkev == null) return false;

                if (imctx != null && gdkev != null && imctx.filter_keypress (gdkev.key)) {
                    return true;
                }

                if (type == Clutter.EventType.KEY_PRESS && 
                        event.key.keyval == Clutter.Key.Return) {
                    if (imctx != null) imctx.reset ();
                }
            }
            return false;
        }

        public override bool button_press_event (Clutter.ButtonEvent event)
        {
            scan_impanel ();

            if (imctx != null) {
                var imm = imctx as Gtk.IMMulticontext;

                Meta.verbose ("%s, ctxid = %s\n", Log.METHOD,
                        imm.get_context_id ());

                if (imm.get_context_id () == null) {
                    imm.set_context_id ("fcitx");
                }
                imctx.reset ();
            }
            return base.button_press_event (event);
        }

		public override void key_focus_in ()
		{
            Meta.verbose ("imtext: %s\n", Log.METHOD);
            if (editable && imctx != null) {
                imctx.focus_in ();
            }
            base.key_focus_in ();
		}

		public override void key_focus_out ()
		{
            Meta.verbose ("imtext: %s\n", Log.METHOD);
            if (editable && im_clone != null) {
                im_clone.hide ();
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
                if (imctx != null)
                    imctx.set_client_window (event_window);
            }
		}

		public override void unrealize ()
		{
            if (event_window != null) {
                imctx.reset ();
                destroy_context ();
                event_window.destroy ();
                event_window = null;
            }

		}
	}
}

