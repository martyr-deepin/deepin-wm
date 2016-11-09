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
using Meta;

namespace Gala
{
    [DBus (name = "com.deepin.menu.Manager")]
    interface MenuManagerInterface : Object 
    {
        public abstract string RegisterMenu() throws IOError;
    }

    [DBus (name = "com.deepin.menu.Menu")]
    interface MenuInterface : Object 
    {
        public abstract void ShowMenu(string menu_json_content) throws IOError;
		public signal void ItemInvoked(string item_id, bool checked);
		public signal void MenuUnregistered();
	}

	public class MenuItem : Object 
    {
		public string id;
		public string text;
        public bool visible = true;
		
		public MenuItem(string item_id, string item_text) {
			id = item_id;
			text = item_text;
		}
	}

	public class CheckMenuItem : MenuItem 
    {
        public bool checked = false;
		public CheckMenuItem(string item_id, string item_text) {
            base (item_id, item_text);
		}
	}

	public class DeepinWindowMenu : Object
	{
		MenuInterface menu_interface;
		
		public Meta.Window current_window {
			get {
				return _current_window;
			}
			set {
				_current_window = value;
				update_window ();
			}
		}

        List<MenuItem> menu_content;

		MenuItem minimize;
		MenuItem maximize;
		MenuItem move;
		MenuItem resize;
		CheckMenuItem always_on_top;
		CheckMenuItem on_visible_workspace;
		MenuItem move_left;
		MenuItem move_right;
		MenuItem close;
		Meta.Window _current_window;

        construct
        {
            menu_content = new List<MenuItem>();
            minimize = new MenuItem("minimize", _("Mi_nimize"));
            menu_content.append(minimize);
            maximize = new MenuItem("maximize", "");
            menu_content.append(maximize);
            move = new MenuItem("move", _("_Move"));
            menu_content.append(move);
            resize = new MenuItem("resize", _("_Resize"));
            menu_content.append(resize);
            always_on_top = new CheckMenuItem("always_on_top", _("Always on _Top"));
            menu_content.append(always_on_top);
            on_visible_workspace = new CheckMenuItem("on_visible_workspace", _("_Always on Visible Workspace"));
            menu_content.append(on_visible_workspace);
            move_left = new MenuItem("move_left", _("Move to Workspace _Left"));
            menu_content.append(move_left);
            move_right = new MenuItem("move_right", _("Move to Workspace R_ight"));
            menu_content.append(move_right);
            close = new MenuItem("close", _("_Close"));
            menu_content.append(close);
        }

		public void Menu(int menu_x, int menu_y) 
        {
            if (current_window.window_type == WindowType.DESKTOP ||
                    current_window.window_type == WindowType.DOCK ||
                    current_window.window_type == WindowType.SPLASHSCREEN) {
                return;
            }

			try {
			    MenuManagerInterface manager = Bus.get_proxy_sync(BusType.SESSION,
                        "com.deepin.menu", "/com/deepin/menu");
			    string menu_object_path = manager.RegisterMenu();
				
				menu_interface = Bus.get_proxy_sync(BusType.SESSION, "com.deepin.menu", menu_object_path);
			    menu_interface.ItemInvoked.connect(handle_item_click);
				menu_interface.MenuUnregistered.connect(() => {
                        //do something
                });
			} catch (IOError e) {
				stderr.printf ("%s\n", e.message);
			}
			
			show_menu(menu_x, menu_y, menu_content);
		}
		
        private void handle_item_click(string item_id, bool checked) 
        {
            stdout.printf("%s clicked, checked %d\n", item_id, (int)checked);
            switch(item_id) {
                case "minimize":
                    current_window.minimize (); break;
                case "maximize":
                    if (current_window.get_maximized () > 0)
                        current_window.unmaximize (Meta.MaximizeFlags.BOTH);
                    else
                        current_window.maximize (Meta.MaximizeFlags.BOTH);
                    break;
                case "move":
                    current_window.begin_grab_op (Meta.GrabOp.KEYBOARD_MOVING, true,
                            Gtk.get_current_event_time ());
                    break;
                case "resize":
                    current_window.begin_grab_op (Meta.GrabOp.KEYBOARD_RESIZING_UNKNOWN, true,
                            Gtk.get_current_event_time ());
                    break;
                case "always_on_top":
                    if (current_window.is_above ())
                        current_window.unmake_above ();
                    else
                        current_window.make_above ();
                    break;
                case "on_visible_workspace":
                    if (current_window.on_all_workspaces)
                        current_window.unstick ();
                    else
                        current_window.stick ();
                    break;
                case "move_left":
                    var wp = current_window.get_workspace ().get_neighbor (Meta.MotionDirection.LEFT);
                    if (wp != null)
                        current_window.change_workspace (wp);
                    break;
                case "move_right":
                    var wp = current_window.get_workspace ().get_neighbor (Meta.MotionDirection.RIGHT);
                    if (wp != null)
                        current_window.change_workspace (wp);
                    break;
                case "close":
                    current_window.@delete (Gtk.get_current_event_time ());
                    break;
			}
        }

	    public void show_menu(int x, int y, List<MenuItem> menu_content) 
        {
	    	try {
	    	    Json.Builder builder = new Json.Builder();
	    	    
	            builder.begin_object();
	    	    
	            builder.set_member_name("x");
	            builder.add_int_value(x);
	    	    
	            builder.set_member_name("y");
	            builder.add_int_value(y);
	    	    
	            builder.set_member_name("isDockMenu");
	            builder.add_boolean_value(false);
	    		
	    		builder.set_member_name("menuJsonContent");
	    		builder.add_string_value(get_items_node(menu_content));
	    	    
	    	    builder.end_object ();
	            
	    	    Json.Generator generator = new Json.Generator();
	            Json.Node root = builder.get_root();
	            generator.set_root(root);
	            
	            string menu_json_content = generator.to_data(null);
	    		
	    	    menu_interface.ShowMenu(menu_json_content);
	    	} catch (IOError e) {
	    		stderr.printf ("%s\n", e.message);
	    	}
	    }

	    public string get_items_node(List<MenuItem> menu_content) 
        {
	    	Json.Builder builder = new Json.Builder();
	    	    
	        builder.begin_object();
	    	
	        builder.set_member_name("items");
	    	builder.begin_array ();
	    	foreach (MenuItem item in menu_content) {
                if (item.visible) builder.add_value(get_item_node(item));
	    	}
	    	builder.end_array ();
	    	
	    	builder.end_object ();
	        
	    	Json.Generator generator = new Json.Generator();
	    	generator.set_root(builder.get_root());
	    	
	        return generator.to_data(null);
	    }
	    
	    public Json.Node get_item_node(MenuItem item) 
        {
	    	Json.Builder builder = new Json.Builder();
	    	
	    	builder.begin_object();
	    	
	        builder.set_member_name("itemId");
	    	builder.add_string_value(item.id);
	    	
	        builder.set_member_name("itemText");
	    	builder.add_string_value(item.text);
	    	
	        builder.set_member_name("itemIcon");
	    	builder.add_string_value("");
	    
	        builder.set_member_name("itemIconHover");
	    	builder.add_string_value("");
	    	
	        builder.set_member_name("itemIconInactive");
	    	builder.add_string_value("");
	    	
	        builder.set_member_name("itemExtra");
	    	builder.add_string_value("");
	    	
            builder.set_member_name("isActive");
            builder.add_boolean_value(true);

	    	if (item.id == "always_on_top" || item.id == "on_visible_workspace") {
                builder.set_member_name("isCheckable");
                builder.add_boolean_value(true);

                builder.set_member_name("checked");
                builder.add_boolean_value((item as CheckMenuItem).checked);
            }
	    
	    	builder.end_object ();
	        
	        return builder.get_root();
	    }		

		void update_window ()
		{
            var screen = current_window.get_screen ();

			minimize.visible = current_window.can_minimize ();

			maximize.visible = current_window.can_maximize ();
			maximize.text = current_window.get_maximized () > 0 ? _("Unma_ximize") : _("Ma_ximize");

			move.visible = current_window.allows_move ();

			resize.visible = current_window.allows_resize ();

			always_on_top.checked = current_window.is_above ();

            on_visible_workspace.visible = screen.get_n_workspaces () > 1;
			on_visible_workspace.checked = current_window.on_all_workspaces;

			move_right.visible = !current_window.on_all_workspaces && 
                screen.get_active_workspace_index () < screen.get_n_workspaces () - 1;

			move_left.visible = !current_window.on_all_workspaces && 
                screen.get_active_workspace_index ()  > 0;

			close.visible = current_window.can_close ();
		}
	}
}

