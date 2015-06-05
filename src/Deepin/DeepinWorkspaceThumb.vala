//
//  Copyright (C) 2014 Xu Fasheng, Deepin, Inc.
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
	 * Workspace thumnail clone with background and normal windows.
	 * It also includes the drawing code for the active highlight.
	 */
	public class DeepinWorkspaceThumb : Actor
	{
		// TODO:
		// public static const int SIZE = 64;
		public static const int SIZE = 192;

		// TODO:
		static const int PLUS_SIZE = 8;
		static const int PLUS_WIDTH = 24;

		const int SHOW_CLOSE_BUTTON_DELAY = 200;

		/**
		 * The group has been clicked. The MultitaskingView should consider activating
		 * its workspace.
		 */
		public signal void selected ();

		public Workspace workspace { get; construct; }

		// TODO: remove
		// static Gtk.StyleContext? style_context = null;

		Actor active_shape;
		Actor close_button;

		// TODO: use workspace_clone instead
		Actor window_container;
		Actor background;

		uint show_close_button_timeout = 0;

		public DeepinWorkspaceThumb (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			// TODO: size
			width = SIZE;
			height = SIZE;
			reactive = true;

			// active shape
			active_shape = new DeepinCssStaticActor ("deepin-workspace-thumb", Gtk.StateFlags.SELECTED);
			active_shape.opacity = 0;
			add_child (active_shape);

			// background
			background = new DeepinFramedBackground (workspace.get_screen (), false);
			// background.reactive = true;// TODO:
			// background.button_press_event.connect (() => {
			// 	selected (true);
			// 	return false;
			// });
			double scale = ((double) SIZE) / background.width;
			background.scale_x = scale;
			background.scale_y = scale;
			add_child (background);

			// TODO:
			var click = new ClickAction ();
			click.clicked.connect (() => selected ());
			// when the actor is pressed, the ClickAction grabs all events, so we won't be
			// notified when the cursor leaves the actor, which makes our close button stay
			// forever. To fix this we hide the button for as long as the actor is pressed.
			click.notify["pressed"].connect (() => {
				toggle_close_button (!click.pressed && get_has_pointer ());
			});
			add_action (click);

			window_container = new Actor ();
			window_container.width = width;
			window_container.height = height;

			add_child (window_container);

			// TODO:
			close_button = Utils.create_close_button ();
			close_button.x = -Math.floorf (close_button.width * 0.4f);
			close_button.y = -Math.floorf (close_button.height * 0.4f);
			close_button.opacity = 0;
			close_button.reactive = true;
			close_button.visible = false;
			close_button.set_easing_duration (200);

			// block propagation of button presses on the close button, otherwise
			// the click action on the icon group will act weirdly
			close_button.button_press_event.connect (() => { return true; });

			add_child (close_button);

			var close_click = new ClickAction ();
			close_click.clicked.connect (close);
			close_button.add_action (close_click);
		}

		~DeepinWorkspaceThumb ()
		{
			background.destroy ();
		}

		public override bool enter_event (CrossingEvent event)
		{
			toggle_close_button (true);
			return false;
		}

		public override bool leave_event (CrossingEvent event)
		{
			if (!contains (event.related))
				toggle_close_button (false);

			return false;
		}

		public void set_active (bool value, bool animate = true)
		{
			if (animate) {
				active_shape.save_easing_state ();
				active_shape.set_easing_duration (1000); // TODO
			}

			active_shape.opacity = value ? 255 : 0;

			if (animate) {
				active_shape.restore_easing_state ();
			}
		}

		// TODO:
		/**
		 * Requests toggling the close button. If show is true, a timeout will be set after which
		 * the close button is shown, if false, the close button is hidden and the timeout is removed,
		 * if it exists. The close button may not be shown even though requested if the workspace has
		 * no windows or workspaces aren't set to be dynamic.
		 *
		 * @param show Whether to show the close button
		 */
		void toggle_close_button (bool show)
		{
			// don't display the close button when we don't have dynamic workspaces
			// or when there are no windows on us. For one, our method for closing
			// wouldn't work anyway without windows and it's also the last workspace
			// which we don't want to have closed if everything went correct
			if (!Prefs.get_dynamic_workspaces () || window_container.get_n_children () < 1)
				return;

			if (show_close_button_timeout != 0) {
				Source.remove (show_close_button_timeout);
				show_close_button_timeout = 0;
			}

			if (show) {
				show_close_button_timeout = Timeout.add (SHOW_CLOSE_BUTTON_DELAY, () => {
					close_button.visible = true;
					close_button.opacity = 255;
					show_close_button_timeout = 0;
					return false;
				});
				return;
			}

			close_button.opacity = 0;
			var transition = get_transition ("opacity");
			if (transition != null)
				transition.completed.connect (() => {
					close_button.visible = false;
				});
			else
				close_button.visible = false;
		}

		/**
		 * Remove all currently added WindowIconActors
		 */
		public void clear ()
		{
			window_container.destroy_all_children ();
		}

		// TODO: remove argument need_redraw
		/**
		 * Creates a Clone for the given window and adds it to the group
		 *
		 * @param window      The MetaWindow for which to create the Clone
		 * @param need_redraw If you add multiple windows at once you may want to consider
		 *                    settings this to true and when done calling redraw() manually
		 */
		public void add_window (Window window, bool need_redraw = true)
		{
			// TODO:
			// var actor = window.get_compositor_private () as WindowActor;
			// var new_window = new Clone (actor.get_texture ());

			// hide shadown and icon for window clone
			var new_window = new DeepinWindowClone (window, false, false);
			new_window.scale_x = 0.1; // TODO
			new_window.scale_y = 0.1;

			new_window.save_easing_state ();
			new_window.set_easing_duration (0);
			new_window.set_position (32, 32);
			new_window.restore_easing_state ();

			window_container.add_child (new_window);
		}

		/**
		 * Remove the Clone for a MetaWindow from the group
		 *
		 * @param animate Whether to fade the icon out before removing it
		 */
		public void remove_window (Window window, bool animate = true)
		{
			foreach (var child in window_container.get_children ()) {
				unowned DeepinWindowClone w = (DeepinWindowClone) child;
				if (w.window == window) {
					if (animate) {
						w.set_easing_mode (AnimationMode.LINEAR);
						w.set_easing_duration (200);
						w.opacity = 0;

						var transition = w.get_transition ("opacity");
						if (transition != null) {
							transition.completed.connect (() => {
								w.destroy ();
							});
						} else {
							w.destroy ();
						}

					} else
						w.destroy ();

					// don't break here! If people spam hover events and we animate
					// removal, we can actually multiple instances of the same window icon
				}
			}
		}

		// TODO: close workspace action
		/**
		 * Close handler. We close the workspace by deleting all the windows on it.
		 * That way the workspace won't be deleted if windows decide to ignore the
		 * delete signal
		 */
		void close ()
		{
			var time = workspace.get_screen ().get_display ().get_current_time ();
			foreach (var window in workspace.list_windows ()) {
				var type = window.window_type;
				if (!window.is_on_all_workspaces () && (type == WindowType.NORMAL
					|| type == WindowType.DIALOG || type == WindowType.MODAL_DIALOG))
					window.@delete (time);
			}
		}

		// TODO:
		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var shape_box = ActorBox ();
			shape_box.set_size (box.get_width (), box.get_height ());
			shape_box.set_origin (0, 0);
			active_shape.allocate (shape_box, flags);
		}
	}
}
