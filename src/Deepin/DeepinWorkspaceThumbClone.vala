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
	 * Workspace thumnail clone with background, normal windows and workspace names.  It also
	 * support dragging and dropping to move and close workspaces.
	 */
	public class DeepinWorkspaceThumbClone : Actor
	{
		const int WORKSPACE_NAME_WIDTH = 70;
		const int WORKSPACE_NAME_HEIGHT = 8;  // will pluse NAME_SHAPE_PADDING * 2 when using
		const int WORKSPACE_NAME_MAX_LENGTH = 32;

		// distance between thumbnail workspace clone and workspace name field
		const int WORKSPACE_NAME_DISTANCE = 16;

		// layout spacing for workspace name field
		const int WORKSPACE_NAME_SPACING = 5;

		const int THUMB_SHAPE_PADDING = 2;
		const int NAME_SHAPE_PADDING = 8;

		/**
		 * The group has been clicked. The MultitaskingView should consider activating its
		 * workspace.
		 */
		public signal void selected ();

		public Workspace workspace
		{
			get;
			construct;
		}

		public Actor? fallback_key_focus = null;

		// selected shape for workspace thumbnail clone
		Actor thumb_shape;

		// selected shape for workspace name field
		DeepinCssActor name_shape;

		Actor workspace_shadow;
		Actor workspace_clone;
		Actor background;
		DeepinWindowCloneThumbContainer window_container;

		Actor workspace_name;
		Text workspace_name_num;
		Text workspace_name_text;
		int workspace_name_width;
		int workspace_name_height;

		Actor close_button;

		uint show_close_button_timeout_id = 0;

		public DeepinWorkspaceThumbClone (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			reactive = true;

			// workspace shadow effect
			workspace_shadow = new Actor ();
			workspace_shadow.add_effect_with_name (
				"shadow", new ShadowEffect (get_thumb_workspace_prefer_width (),
											get_thumb_workspace_prefer_heigth (), 10, 1));
			workspace_shadow.opacity = 76;
			add_child (workspace_shadow);

			workspace.get_screen ().monitors_changed.connect (update_workspace_shadow);

			// selected shape for workspace thumbnail clone
			thumb_shape =
				new DeepinCssStaticActor ("deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
			thumb_shape.opacity = 0;
			thumb_shape.set_easing_mode (DeepinMultitaskingView.WORKSPACE_ANIMATION_MODE);
			add_child (thumb_shape);

			// workspace thumbnail clone
			workspace_clone = new Actor ();
			int radius = DeepinUtils.get_css_border_radius (
				"deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
			workspace_clone.add_effect (new DeepinRoundRectEffect (radius));
			add_child (workspace_clone);

			background = new DeepinFramedBackground (workspace.get_screen (), false, false);
			background.button_press_event.connect (() => {
				selected ();
				return true;
			});
			workspace_clone.add_child (background);

			window_container = new DeepinWindowCloneThumbContainer (workspace);
			window_container.window_activated.connect ((w) => selected ());
			workspace_clone.add_child (window_container);

			// selected shape for workspace name field
			name_shape = new DeepinCssActor ("deepin-workspace-thumb-clone-name");
			name_shape.reactive = true;
			name_shape.set_easing_mode (DeepinMultitaskingView.WORKSPACE_ANIMATION_MODE);

			name_shape.button_press_event.connect (on_name_button_press_event);

			add_child (name_shape);

			// workspace name field
			workspace_name = new Actor ();
			workspace_name.layout_manager = new BoxLayout ();

			var name_font = DeepinUtils.get_css_font ("deepin-workspace-thumb-clone-name");

			workspace_name_num = new Text ();
			workspace_name_num.set_easing_mode (DeepinMultitaskingView.WORKSPACE_ANIMATION_MODE);
			workspace_name_num.set_font_description (name_font);

			workspace_name_text = new Text ();
			workspace_name_text.reactive = true;
			workspace_name_text.activatable = true;
			workspace_name_text.cursor_size = 1;
			workspace_name_text.ellipsize = Pango.EllipsizeMode.END;
			workspace_name_text.max_length = WORKSPACE_NAME_MAX_LENGTH;
			workspace_name_text.single_line_mode = true;
			workspace_name_text.set_easing_mode (DeepinMultitaskingView.WORKSPACE_ANIMATION_MODE);
			workspace_name_text.set_font_description (name_font);
			workspace_name_text.selection_color =
				DeepinUtils.get_css_background_color ("deepin-text-selection");
			workspace_name_text.selected_text_color =
				DeepinUtils.get_css_color ("deepin-text-selection");

			workspace_name_text.button_press_event.connect (on_name_button_press_event);
			workspace_name_text.activate.connect (() => {
				get_stage ().set_key_focus (fallback_key_focus);
				workspace_name_text.editable = false;
				// TODO: relayout
				workspace_name.queue_relayout ();
			});
			workspace_name_text.key_focus_in.connect (() => {
				// make cursor visible even through workspace name is empty, maybe this is a bug of
				// Clutter.Text
				if (workspace_name_text.text.length == 0) {
					workspace_name_text.text = " ";
					workspace_name_text.text = "";
				}
			});
			workspace_name_text.key_focus_out.connect (() => {
				set_workspace_name ();
				workspace_name.queue_relayout ();

				stdout.printf ("name queue relayout..%d\n", workspace.index () + 1);  // TODO:
			});

			get_workspace_name ();

			workspace_name.add_child (workspace_name_num);
			workspace_name.add_child (workspace_name_text);
			add_child (workspace_name);

			// close button
			close_button = Utils.create_close_button ();
			close_button.reactive = true;
			close_button.opacity = 0;

			// block propagation of button presses on the close button, otherwise the click action
			// on the WorkspaceTHumbClone will act weirdly close_button.button_press_event.connect
			// (() => { return true; });
			close_button.button_press_event.connect (() => {
				remove_workspace ();
				return true;
			});

			add_child (close_button);

			var click = new ClickAction ();
			click.clicked.connect (() => selected ());
			add_action (click);
		}

		~DeepinWorkspaceThumbClone ()
		{
			workspace.get_screen ().monitors_changed.disconnect (update_workspace_shadow);
			background.destroy ();
		}

		public override bool enter_event (CrossingEvent event)
		{
			// don't display the close button when we have dynamic workspaces or when there is only
			// one workspace
			if (Prefs.get_dynamic_workspaces () || Prefs.get_num_workspaces () == 1) {
				return false;
			}

			close_button.save_easing_state ();

			close_button.set_easing_duration (300);
			close_button.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
			close_button.opacity = 255;

			close_button.restore_easing_state ();

			return false;
		}

		public override bool leave_event (CrossingEvent event)
		{
			close_button.save_easing_state ();

			close_button.set_easing_duration (300);
			close_button.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
			close_button.opacity = 0;

			close_button.restore_easing_state ();

			return false;
		}

		bool on_name_button_press_event ()
		{
			if (workspace_name_text.editable && workspace_name_text.has_key_focus ()) {
				return false;
			}

			grab_key_focus_for_name ();

			// select current workspace if workspace name is editable
			selected ();

			// Return false to let event continue to be passed, so the cursor will be put in the
			// position of the mouse.
			return false;
		}

		public void grab_key_focus_for_name ()
		{
			workspace_name_text.grab_key_focus ();
			workspace_name_text.editable = true;
		}

		public void set_workspace_name ()
		{
			Prefs.change_workspace_name (workspace.index (), workspace_name_text.text);
		}

		public void get_workspace_name ()
		{
			workspace_name_num.text = "%d".printf (workspace.index () + 1);
			workspace_name_text.text = DeepinUtils.get_workspace_name (workspace.index ());
		}

		public void select (bool value, bool animate = true)
		{
			int duration = animate ? AnimationSettings.get_default ().workspace_switch_duration : 0;

			// selected shape for workspace thumbnail clone
			thumb_shape.save_easing_state ();

			thumb_shape.set_easing_duration (duration);
			thumb_shape.opacity = value ? 255 : 0;

			thumb_shape.restore_easing_state ();

			// selected shape for workspace name field
			name_shape.save_easing_state ();

			name_shape.set_easing_duration (duration);
			name_shape.select = value;

			name_shape.restore_easing_state ();

			// font color for workspace name field
			workspace_name_num.save_easing_state ();
			workspace_name_text.save_easing_state ();

			workspace_name_num.set_easing_duration (duration);
			workspace_name_text.set_easing_duration (duration);
			var text_color = DeepinUtils.get_css_color ("deepin-workspace-thumb-clone-name",
				value ? Gtk.StateFlags.SELECTED : Gtk.StateFlags.NORMAL);
			workspace_name_num.color = text_color;
			workspace_name_text.color = text_color;

			workspace_name_num.restore_easing_state ();
			workspace_name_text.restore_easing_state ();
		}

		public void select_window (Window window)
		{
			window_container.select_window (window);
		}

		void update_workspace_shadow ()
		{
			var shadow_effect = workspace_clone.get_effect ("shadow") as ShadowEffect;
			if (shadow_effect != null) {
				shadow_effect.update_size (
					get_thumb_workspace_prefer_width (), get_thumb_workspace_prefer_heigth ());
			}
		}

		int get_thumb_workspace_prefer_width ()
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
			return (int)(monitor_geom.width *
				DeepinWorkspaceThumbCloneContainer.WORKSPACE_WIDTH_PERCENT);
		}

		int get_thumb_workspace_prefer_heigth ()
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
			return (int)(monitor_geom.height *
				DeepinWorkspaceThumbCloneContainer.WORKSPACE_WIDTH_PERCENT);
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

		/*
		 * Remove current workspace and moving all the windows to preview workspace.
		 */
		void remove_workspace ()
		{
			if (Prefs.get_num_workspaces () <= 1) {
				// there is only one workspace, just ignore
				return;
			}

			// Ensure workspace name field lost focus to avoid invalid operations even though the
			// workspace already not exists.
			get_stage ().set_key_focus (fallback_key_focus);

			// TODO: animation
			opacity = 0;
			var transition = workspace_clone.get_transition ("opacity");
			if (transition != null) {
				// stdout.printf ("transition is not null\n");// TODO:
				transition.completed.connect (
					() => DeepinUtils.remove_workspace (workspace.get_screen (), workspace));
			} else {
				// stdout.printf ("transition is null\n");// TODO:
				DeepinUtils.remove_workspace (workspace.get_screen (), workspace);
			}
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
			float scale =
				box.get_width () != 0 ? box.get_width () / (float)monitor_geom.width : 0.5f;

			// calculate monitor width height ratio
			float monitor_whr = (float)monitor_geom.height / monitor_geom.width;

			// alocate workspace clone
			var thumb_box = ActorBox ();
			float thumb_width = box.get_width ();
			float thumb_height = thumb_width * monitor_whr;
			thumb_box.set_size (thumb_width, thumb_height);
			thumb_box.set_origin (0, 0);
			workspace_clone.allocate (thumb_box, flags);
			workspace_shadow.allocate (thumb_box, flags);
			window_container.allocate (thumb_box, flags);

			// scale background
			background.scale_x = scale;
			background.scale_y = scale;

			var thumb_shape_box = ActorBox ();
			thumb_shape_box.set_size (
				thumb_width + THUMB_SHAPE_PADDING * 2, thumb_height + THUMB_SHAPE_PADDING * 2);
			thumb_shape_box.set_origin (
				(box.get_width () - thumb_shape_box.get_width ()) / 2, -THUMB_SHAPE_PADDING);
			thumb_shape.allocate (thumb_shape_box, flags);

			var close_box = ActorBox ();
			close_box.set_size (close_button.width, close_button.height);
			close_box.set_origin (
				box.get_width () - close_box.get_width () * 0.60f, -close_button.height * 0.40f);
			close_button.allocate (close_box, flags);

			var name_shape_box = ActorBox ();
			name_shape_box.set_size (WORKSPACE_NAME_WIDTH + NAME_SHAPE_PADDING * 2,
									 WORKSPACE_NAME_HEIGHT + NAME_SHAPE_PADDING * 2);
			name_shape_box.set_origin ((box.get_width () - name_shape_box.get_width ()) / 2,
									   thumb_box.y2 + WORKSPACE_NAME_DISTANCE);
			name_shape.allocate (name_shape_box, flags);

			var name_box = ActorBox ();
			name_box.set_size (
				Math.fminf (workspace_name.width, WORKSPACE_NAME_WIDTH), workspace_name.height);
			name_box.set_origin (
				(box.get_width () - name_box.get_width ()) / 2,
				name_shape_box.y1 + (name_shape_box.get_height () - name_box.get_height ()) / 2);
			workspace_name.allocate (name_box, flags);

			// update layout for workspace name field.
			var name_layout = workspace_name.layout_manager as BoxLayout;
			if (workspace_name_text.text.length > 0 || workspace_name_text.editable) {
				name_layout.spacing = WORKSPACE_NAME_SPACING;
			} else {
				name_layout.spacing = 0;
			}
		}
	}
}
