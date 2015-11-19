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

namespace Gala
{
	public class BackgroundManager : Meta.BackgroundGroup
	{
		const string BACKGROUND_SCHEMA = "com.deepin.wrap.gnome.desktop.background";
		const string EXTRA_BACKGROUND_SCHEMA = "com.deepin.dde.appearance";
		const int FADE_ANIMATION_TIME = 1000;

		public signal void changed ();

		public Meta.Screen screen { get; construct; }
		public int monitor_index { get; construct; }
		public int workspace_index { get; construct; }
		public bool control_position { get; construct; }

        Gee.ArrayList<Meta.BackgroundActor>? actors;

		BackgroundSource background_source;
        ulong changed_handler = 0;
        ulong serial = 0;

		public BackgroundManager (Meta.Screen screen, int monitor_index, int workspace_index,
								  bool control_position = true)
		{
			Object (screen: screen, monitor_index: monitor_index, workspace_index: workspace_index,
					control_position: control_position);
		}

		construct
		{
			background_source = BackgroundCache.get_default ().get_background_source (
				screen, BACKGROUND_SCHEMA, EXTRA_BACKGROUND_SCHEMA);

			changed_handler = background_source.changed.connect (() => {
                create_background_actor ();
                //new_background_actor.vignette_sharpness = background_actor.vignette_sharpness;
                //new_background_actor.brightness = background_actor.brightness;
                //new_background_actor.visible = background_actor.visible;
			});

            actors = new Gee.ArrayList<Meta.BackgroundActor> ();
            create_background_actor ();
		}

		public override void destroy ()
		{
            SignalHandler.disconnect (background_source, changed_handler);
            changed_handler = 0;

			BackgroundCache.get_default ().release_background_source (
                    BACKGROUND_SCHEMA, EXTRA_BACKGROUND_SCHEMA);
			background_source = null;

            actors.clear ();
            actors = null;

			base.destroy ();
		}

		void create_background_actor ()
		{
            Meta.verbose ("%s: count %d\n", Log.METHOD, actors.size);

			var background = background_source.get_background (monitor_index, workspace_index);
			var background_actor = new Meta.BackgroundActor (screen, monitor_index);
            background_actor.name = @"bg$serial";
            serial++;

			// TODO: test blur effect
			// DeepinBlurEffect.setup (background_actor, 20.0f, 1);

			background_actor.background = background.background;

			var monitor = screen.get_monitor_geometry (monitor_index);
			background_actor.set_size (monitor.width, monitor.height);

			if (control_position) {
				background_actor.set_position (monitor.x, monitor.y);
			}

            ulong loaded_handler = 0;
            loaded_handler = background.loaded.connect (() => {
                SignalHandler.disconnect (background, loaded_handler);
                loaded_handler = 0;

                insert_child_below (background_actor, null);
                actors.add (background_actor);
                Meta.verbose ("%s: add %s\n", Log.METHOD, background_actor.name);

                while (actors.size > 2) {
                    Meta.verbose ("remove_child %s\n", actors[0].name);
                    var actor = actors[0];
                    actor.visible = false;
                    actor.opacity = 0;

                    actors.remove_at (0);
                    actor.remove_all_transitions ();
                    remove_child (actor);

                    actor.destroy ();
                }

                if (actors.size > 1) {
                    var actor = actors[actors.size - 2];

                    actor.opacity = 255;
                    actor.save_easing_state ();
                    actor.set_easing_duration (FADE_ANIMATION_TIME);
                    actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
                    actor.opacity = 0;
                    actor.restore_easing_state ();

                    actor.transition_stopped.connect( (name, is_finished) => {
                        Meta.verbose ("swapping from %s, completed = %d\n",
                                actor.name, is_finished);
                        if (is_finished) {
                            //queue_relayout ();
                            Meta.verbose ("leftout actors\n");
                            var children = get_children ();
                            children.foreach ((c) => {
                                Meta.verbose ("actor %s\n", c.name);
                            });

                            actor.visible = false;
                            assert (actor.opacity == 0);

                            actors.remove (actor);
                            remove_child (actor);

                            Idle.add( () => { actor.destroy (); return false; });

                            changed ();

                        } else {
                            actor.opacity = 0;
                        }
                    });

                } 
                
            });

            background_actor.destroy.connect (() => {
                Meta.verbose ("%s: destroy %s\n", Log.METHOD, background_actor.name);
                if (loaded_handler != 0) 
                    SignalHandler.disconnect (background, loaded_handler);
            });
		}
	}
}
