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
		public const string BACKGROUND_SCHEMA = "com.deepin.wrap.gnome.desktop.background";
		public const string EXTRA_BACKGROUND_SCHEMA = "com.deepin.dde.appearance";
		const int FADE_ANIMATION_TIME = 1000;

		public signal void changed ();

		public Meta.Screen screen { get; construct; }
		public int monitor_index { get; construct; }
		public int workspace_index { get; construct; }
		public bool control_position { get; construct; }
        public float background_scale { get; construct; }

        protected Gee.ArrayList<Meta.BlurredBackgroundActor>? actors;

		BackgroundSource? background_source = null;
        ulong changed_handler = 0;
        ulong serial = 0;
		int radius = 0;
		int rounds = 0;
        protected int rounded_radius = 0;
        unowned Meta.Workspace workspace;

		public BackgroundManager (Meta.Screen screen, int monitor_index, int workspace_index,
								  bool control_position = true, float background_scale = 1.0f)
		{
			Object (screen: screen, monitor_index: monitor_index, workspace_index: workspace_index,
					control_position: control_position, background_scale: background_scale);
		}

		construct
		{
            workspace = screen.get_workspace_by_index (workspace_index);
            workspace.notify["workspace-index"].connect_after (on_workspace_index_changed);

			background_source = BackgroundCache.get_default ().get_background_source (
				screen, BACKGROUND_SCHEMA, EXTRA_BACKGROUND_SCHEMA);

			changed_handler = background_source.changed.connect ((indexes) => {
                foreach (var idx in indexes) {
                    if (idx == workspace_index) {
                        create_background_actor ();
                        break;
                    }
                }
            });

            actors = new Gee.ArrayList<Meta.BlurredBackgroundActor> ();
            create_background_actor ();
		}

		~BackgroundManager ()
		{
            background_source.changed.disconnect (create_background_actor);
            workspace.notify["workspace-index"].disconnect (on_workspace_index_changed);
            changed_handler = 0;

			BackgroundCache.get_default ().release_background_source (
                    BACKGROUND_SCHEMA, EXTRA_BACKGROUND_SCHEMA);

            actors.clear ();
            actors = null;
		}

        void on_workspace_index_changed(Object o, ParamSpec p)
        {
            _workspace_index = workspace.index ();
            Idle.add(() => {
                if (actors.size > 0) {
                    var actor = actors[actors.size - 1];
                    var background = background_source.get_background (monitor_index, workspace_index);
                    actor.background = background.background;
                }
                return false;
            });
        }

        public void set_transient_background (string uri)
        {
            if (actors.size > 0) {
                var actor = actors[actors.size - 1];
                if (uri.length == 0) {
                    var background = background_source.get_background (
                            monitor_index, workspace_index, uri);
                    actor.background = background.background;
                } else {
                    var background = background_source.get_transient_background (
                            monitor_index, workspace_index, uri);
                    actor.background = background.background;
                }
            }
        }

        public void set_rounds (int rounds)
        {
            this.rounds = rounds;
            if (actors.size > 0) {
                var actor = actors[actors.size - 1];
                actor.set_rounds (rounds);
            }
        }

        // blur radius
        public void set_radius (int radius)
        {
            this.radius = radius;
            if (actors.size > 0) {
                var actor = actors[actors.size - 1];
                actor.set_radius (radius);
            }
        }

        public void set_rounded_radius (int rd)
        {
            rounded_radius = rd;
            if (actors.size == 0) {
                return;
            }

            foreach (var actor in actors) {
                set_actor_rounded_radius (actor, rd);
            }
        }

        Cairo.Region? last_region = null;
        Cairo.Surface? last_blur_mask = null;
        protected void set_actor_rounded_radius (Meta.BlurredBackgroundActor actor, int rd, bool forced = false)
        {
            if (rd == 0) {
                actor.set_blur_mask (null);
            } else {
                Cairo.RectangleInt r =  {0, 0, (int)actor.width, (int)actor.height};
                Cairo.RectangleInt[] rects = { r };
                int[] radius = {rd, rd};

                var region = new Cairo.Region.rectangles (rects);
                if (forced || !region.equal (last_region)) {
                    var blur_mask = DeepinUtils.build_blur_mask (rects, radius);
                    actor.set_blur_mask (blur_mask);
                    last_blur_mask = blur_mask;
                    last_region = region;
                } else {
                    actor.set_blur_mask (last_blur_mask);
                }
            }
        }

        public void add_child_effect_with_name (string name, Clutter.Effect effect)
        {
            if (actors.size > 0) {
                var actor = actors[actors.size - 1];
                actor.add_effect_with_name (name, effect);
            }
        }

        public void remove_child_effect_by_name (string name)
        {
            if (actors.size > 0) {
                var actor = actors[actors.size - 1];
                actor.remove_effect_by_name (name);
            }
        }

        void on_background_actor_loaded (Meta.BlurredBackgroundActor background_actor)
        {
            insert_child_below (background_actor, null);
            actors.add (background_actor);
            set_actor_rounded_radius (background_actor, rounded_radius, true);
            Meta.verbose ("%s: add %s\n", Log.METHOD, background_actor.name);

            while (actors.size > 2) {
                Meta.verbose ("remove_child %s\n", actors[0].name);
                var actor = actors[0];

                actors.remove_at (0);
                actor.remove_all_transitions ();
                remove_child (actor);

                actor.destroy ();
            }

            if (actors.size > 1) {
                var actor = actors[actors.size - 2];

                if (Config.DEEPIN_ARCH.has_prefix("mips")) {
                    Timeout.add (50, () => {actor.visible = false; return false; });
                    changed ();

                } else {
                    actor.opacity = 255;
                    actor.save_easing_state ();
                    actor.set_easing_duration (FADE_ANIMATION_TIME);
                    actor.set_easing_mode (Clutter.AnimationMode.EASE_OUT_QUAD);
                    actor.opacity = 0;
                    actor.restore_easing_state ();

                    actor.transition_stopped.connect ((name, is_finished) => {
                        Meta.verbose ("swapping from %s, completed = %d, leftout actors: \n",
                                actor.name, is_finished);
                        var children = get_children ();
                        children.foreach ((c) => {
                            Meta.verbose ("\tactor %s\n", c.name);
                        });
                        actor.visible = false;
                        changed ();
                    });
                }
            }
        }

        protected void create_background_actor ()
        {
            Meta.verbose ("%s: count %d\n", Log.METHOD, actors.size);

            var background = background_source.get_background (monitor_index, workspace_index);
            var background_actor = new Meta.BlurredBackgroundActor (screen, monitor_index);
            background_actor.name = @"bg$serial";
            serial++;

            var monitor = screen.get_monitor_geometry (monitor_index);
            background_actor.set_size (monitor.width * background_scale, 
                    monitor.height * background_scale);

            if (control_position) {
                background_actor.set_position (monitor.x, monitor.y);
            }
            background_actor.background = background.background;

            ulong loaded_handler = 0;
            if (background.is_loaded) {
                on_background_actor_loaded (background_actor);
            } else {
                loaded_handler = background.loaded.connect (() => {
                    SignalHandler.disconnect (background, loaded_handler);
                    loaded_handler = 0;

                    on_background_actor_loaded (background_actor);
                });
            }

            background_actor.destroy.connect (() => {
                Meta.verbose ("%s: destroy %s\n", Log.METHOD, background_actor.name);
                if (loaded_handler != 0) 
                SignalHandler.disconnect (background, loaded_handler);
            });
        }
	}
}
