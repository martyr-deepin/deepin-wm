//
//  Copyright (C) 2014 Deepin, Inc.
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
	 * Workspace thumnail clone with background, normal windows and
	 * workspace names.  It also support dragging and dropping to
	 * move and close workspaces.
	 */
	public class DeepinWorkspaceThumbClone : Actor
	{
		// TODO:
		// public static const int SIZE = 64;
		public static const int SIZE = 192;

		const int SHAPE_PADDING = 5;

		// TODO: draw plus button
		static const int PLUS_SIZE = 8;
		static const int PLUS_WIDTH = 24;

		const int SHOW_CLOSE_BUTTON_DELAY = 200;

		/**
		 * The group has been clicked. The MultitaskingView should consider activating
		 * its workspace.
		 */
		public signal void selected ();

		public Workspace workspace { get; construct; }

		// TODO:
		Actor shape_thumb;
		DeepinCssActor shape_name;
		Actor close_button;

		// TODO: use workspace_clone instead
		DeepinWindowCloneThumbContainer window_container;
		Actor background;

		uint show_close_button_timeout = 0;

		public DeepinWorkspaceThumbClone (Workspace workspace)
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
			shape_thumb = new DeepinCssStaticActor ("deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
			shape_thumb.opacity = 0;
			shape_thumb.set_easing_mode (DeepinMultitaskingView.WORKSPACE_ANIMATION_MODE);
			add_child (shape_thumb);

			shape_name = new DeepinCssActor ("deepin-workspace-thumb-clone-name");
			shape_name.set_easing_mode (DeepinMultitaskingView.WORKSPACE_ANIMATION_MODE);
			add_child (shape_name);

			// background
			background = new DeepinFramedBackground (workspace.get_screen (), false);
			double scale = ((double) SIZE) / background.width;
			background.scale_x = scale;
			background.scale_y = scale;
			add_child (background);

			var click = new ClickAction ();
			// TODO: merge selected() to set_select()
			click.clicked.connect (() => selected ());
			// when the actor is pressed, the ClickAction grabs all events, so we won't be
			// notified when the cursor leaves the actor, which makes our close button stay
			// forever. To fix this we hide the button for as long as the actor is pressed.
			click.notify["pressed"].connect (() => {
				toggle_close_button (!click.pressed && get_has_pointer ());
			});
			add_action (click);

			window_container = new DeepinWindowCloneThumbContainer (workspace);
			window_container.width = width;
			window_container.height = height;

			add_child (window_container);

			// TODO: show close button
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

		~DeepinWorkspaceThumbClone ()
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
			if (!contains (event.related)) {
				toggle_close_button (false);
			}

			return false;
		}

		public void select (bool value, bool animate = true)
		{
			shape_thumb.save_easing_state ();

			shape_thumb.set_easing_duration (animate ?
				AnimationSettings.get_default ().workspace_switch_duration : 0);
			shape_thumb.opacity = value ? 255 : 0;

			shape_thumb.restore_easing_state ();

			shape_name.save_easing_state ();

			shape_name.set_easing_duration (animate ?
				AnimationSettings.get_default ().workspace_switch_duration : 0);
			shape_name.select = value;

			shape_name.restore_easing_state ();
		}

		public void select_window (Window window)
		{
			window_container.select_window (window);
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
			if (!Prefs.get_dynamic_workspaces () || window_container.get_n_children () < 1) {
				return;
			}

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
			else {
				close_button.visible = false;
			}
		}

		// TODO: necessary?
		/**
		 * Remove all currently added WindowIconActors
		 */
		public void clear ()
		{
			window_container.destroy_all_children ();
		}

		/**
		 * Creates a Clone for the given window and adds it to the group
		 */
		public void add_window (Window window)
		{
			window_container.add_window (window);
		}

		/**
		 * Remove the Clone for a MetaWindow from the container
		 */
		public void remove_window (Window window)
		{
			window_container.remove_window (window);
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
					|| type == WindowType.DIALOG || type == WindowType.MODAL_DIALOG)) {
					window.@delete (time);
				}
			}
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var thumb_box = ActorBox ();
			float thumb_width = box.get_width ();
			float thumb_scale = background.width != 0 ? background.height / background.width : 0.5f;
			float thumb_height = thumb_width * thumb_scale;
			thumb_box.set_size (thumb_width, thumb_height);
			thumb_box.set_origin (0, 0);
			background.allocate (thumb_box, flags);
			window_container.allocate (thumb_box, flags);

			var thumb_shape_box = ActorBox ();
			thumb_shape_box.set_size (thumb_width + SHAPE_PADDING * 2, thumb_height + SHAPE_PADDING * 2);
			thumb_shape_box.set_origin ((box.get_width () - thumb_shape_box.get_width ()) / 2, -SHAPE_PADDING);
			shape_thumb.allocate (thumb_shape_box, flags);

			// TODO: workspace names
			var name_shape_box = ActorBox ();
			name_shape_box.set_size (60, 25);
			name_shape_box.set_origin ((box.get_width () - name_shape_box.get_width ()) / 2, box.get_height () - 50);
			shape_name.allocate (name_shape_box, flags);
		}
	}
}
