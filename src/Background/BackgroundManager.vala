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

		BackgroundSource background_source;
		Meta.BackgroundActor background_actor;
		Meta.BackgroundActor? new_background_actor = null;

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

			background_actor = create_background_actor ();
		}

		public override void destroy ()
		{
			BackgroundCache.get_default ().release_background_source (BACKGROUND_SCHEMA,
																	  EXTRA_BACKGROUND_SCHEMA);
			background_source = null;

			if (new_background_actor != null) {
				new_background_actor.destroy ();
				new_background_actor = null;
			}

			if (background_actor != null) {
				background_actor.destroy ();
				background_actor = null;
			}

			base.destroy ();
		}

		void swap_background_actor ()
		{
			var old_background_actor = background_actor;
			background_actor = new_background_actor;
			new_background_actor = null;

			if (old_background_actor == null)
				return;

			var transition = new Clutter.PropertyTransition ("opacity");
			transition.set_from_value (255);
			transition.set_to_value (0);
			transition.duration = FADE_ANIMATION_TIME;
			transition.progress_mode = Clutter.AnimationMode.EASE_OUT_QUAD;
			transition.remove_on_complete = true;
			transition.completed.connect (() => {
				old_background_actor.destroy ();

				// force to relayout here, or BackgroundManager will keep the old size even through
				// monitor resolution changed
				queue_relayout ();

				changed ();
			});

			old_background_actor.add_transition ("fade-out", transition);
		}

		public void update_background_actor ()
		{
			if (new_background_actor != null) {
				// Skip displaying existing background queued for load
				new_background_actor.destroy ();
				new_background_actor = null;
			}

			new_background_actor = create_background_actor ();
			new_background_actor.vignette_sharpness = background_actor.vignette_sharpness;
			new_background_actor.brightness = background_actor.brightness;
			new_background_actor.visible = background_actor.visible;

			var background = new_background_actor.background.get_data<Background> ("delegate");

			if (background.is_loaded) {
				swap_background_actor ();
				return;
			}

			ulong handler = 0;
			handler = background.loaded.connect (() => {
				SignalHandler.disconnect (background, handler);
				background.set_data<ulong> ("background-loaded-handler", 0);

				swap_background_actor ();
			});
			background.set_data<ulong> ("background-loaded-handler", handler);
		}

		Meta.BackgroundActor create_background_actor ()
		{
			var background = background_source.get_background (monitor_index, workspace_index);
			var background_actor = new Meta.BackgroundActor (screen, monitor_index);
			// TODO: test blur effect
			// DeepinBlurEffect.setup (background_actor, 20.0f, 1);

			background_actor.background = background.background;

			insert_child_below (background_actor, null);

			var monitor = screen.get_monitor_geometry (monitor_index);

			background_actor.set_size (monitor.width, monitor.height);

			if (control_position) {
				background_actor.set_position (monitor.x, monitor.y);
			}

			ulong changed_handler = 0;
			changed_handler = background_source.changed.connect (() => {
				SignalHandler.disconnect (background_source, changed_handler);
				changed_handler = 0;
				update_background_actor ();
			});

			background_actor.destroy.connect (() => {
				if (changed_handler != 0) {
					SignalHandler.disconnect (background_source, changed_handler);
					changed_handler = 0;
				}

				var loaded_handler = background.get_data<ulong> ("background-loaded-handler");
				if (loaded_handler != 0) {
					SignalHandler.disconnect (background, loaded_handler);
					background.set_data<ulong> ("background-loaded-handler", 0);
				}
			});

			return background_actor;
		}
	}
}
