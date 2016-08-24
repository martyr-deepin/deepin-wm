//
//  Copyright (C) 2013 Tom Beckmann, Rico Tzschichholz
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

namespace Gala
{
	public class BackgroundContainer : Object
	{
		public signal void structure_changed ();

		public Meta.Screen screen { get; construct; }

		Gee.HashMap<string,BackgroundManager> backgrounds;

		public BackgroundContainer (Meta.Screen screen)
		{
			Object (screen: screen);
		}

		construct
		{
			backgrounds = new Gee.HashMap<string,BackgroundManager> ();
			screen.monitors_changed.connect (update);
			screen.workspace_added.connect (on_workspace_added);
			screen.workspace_removed.connect (on_workspace_removed);
			screen.workspace_reordered.connect (on_workspace_reordered);
			update ();
		}

		~BackgroundContainer ()
		{
			screen.monitors_changed.disconnect (update);
			screen.workspace_added.disconnect (on_workspace_added);
			screen.workspace_removed.disconnect (on_workspace_removed);
			screen.workspace_reordered.connect (on_workspace_reordered);
		}

		public BackgroundManager? get_default_background ()
		{
			return get_background (0, 0);
		}

		public BackgroundManager? get_background (int monitor_index, int workspace_index)
		{
			string key = @"$monitor_index:$workspace_index";
			if (backgrounds.has_key (key)) {
				return backgrounds[key];
			}
			return null;
		}

		void insert_background (int monitor_index, int workspace_index, BackgroundManager background)
		{
			string key = @"$monitor_index:$workspace_index";
			if (!backgrounds.has_key (key)) {
				backgrounds[key] = background;
			}
		}

		void update ()
		{
			foreach (var background in backgrounds.values) {
                if (background.get_parent () != null) {
                    background.get_parent ().remove_child (background);
                }
                background.destroy ();
			}
			backgrounds.clear ();

			for (var i = 0; i < screen.get_n_monitors (); i++) {
				for (var j = 0; j < screen.get_n_workspaces (); j++) {
					var background = new BackgroundManager (screen, i, j);

					insert_background (i, j, background);
				}
			}

            structure_changed ();
		}

        void on_workspace_reordered (int from, int to)
        {
            update ();
        }

        void on_workspace_removed (int index)
        {
			foreach (var background in backgrounds.values) {
                if (background.get_parent () != null) {
                    background.get_parent ().remove_child (background);
                }
			}

            for (var i = 0; i < screen.get_n_monitors (); i++) {
                string key = @"$i:$index";
                if (backgrounds.has_key (key)) {
                    var background = backgrounds[key];
                    backgrounds.remove (key);
                    if (background.get_parent () != null) {
                        background.get_parent ().remove_child (background);
                    }
                    background.destroy ();
                }
            }

			for (var i = 0; i < screen.get_n_monitors (); i++) {
                for (var j = index+1; j < screen.get_n_workspaces ()+1; j++) {
                    string key = @"$i:$j";
                    if (backgrounds.has_key (key)) {
                        var background = backgrounds[key];

                        string new_key = @"$i:$(j-1)";
                        backgrounds[new_key] = background;
                        backgrounds.remove (key);
                    }
                }
			}
            structure_changed ();
        }

        void on_workspace_added (int index)
        {
			foreach (var background in backgrounds.values) {
                if (background.get_parent () != null) {
                    background.get_parent ().remove_child (background);
                }
			}

			for (var i = 0; i < screen.get_n_monitors (); i++) {
                var background = new BackgroundManager (screen, i, index);
                insert_background (i, index, background);
			}
            structure_changed ();
        }
	}
}
