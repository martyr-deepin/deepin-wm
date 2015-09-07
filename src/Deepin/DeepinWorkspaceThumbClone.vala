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
	 * Workspace thumnail clone with background and normal windows.  It also
	 * support dragging and dropping to move and close workspaces.
	 */
	public class DeepinWorkspaceThumbCloneCore : Actor
	{
		const int THUMB_SHAPE_PADDING = 2;

		/**
		 * The workspace clone has been clicked. The MultitaskingView should consider activating its
		 * workspace.
		 */
		public signal void selected ();

		/**
		 * The workspace clone is closing.
		 */
		public signal void closing ();

		public Workspace workspace { get; construct; }

		public DeepinWindowThumbContainer window_container;

		// selected shape for workspace thumbnail clone
		Actor thumb_shape;

		Actor workspace_shadow;
		Actor workspace_clone;
		Actor background;

		Actor close_button;

		uint show_close_button_timeout_id = 0;

		public DeepinWorkspaceThumbCloneCore (Workspace workspace)
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
			add_child (thumb_shape);

			// workspace thumbnail clone
			workspace_clone = new Actor ();
			workspace_clone.set_pivot_point (0.5f, 0.5f);
			int radius = DeepinUtils.get_css_border_radius (
				"deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
			// TODO: round effect
			// workspace_clone.add_effect (new DeepinRoundRectEffect (radius));

			background = new DeepinFramedBackground (workspace.get_screen (), false, false);
			background.button_press_event.connect (() => {
				selected ();
				return true;
			});
			// TODO: background size
			workspace_clone.add_child (background);

			window_container = new DeepinWindowThumbContainer (workspace);
			window_container.window_activated.connect ((w) => selected ());
			window_container.window_dragging.connect ((w) => {
				// If window is dragging in thumbnail workspace, make close button manually or it
				// will keep shown only mouse move in and out again.
				show_close_button (false);
			});
			workspace_clone.add_child (window_container);

			// TODO:
			add_child (workspace_clone);

			// close button
			close_button = Utils.create_close_button ();
			close_button.reactive = true;
			close_button.opacity = 0;

			// block propagation of button presses on the close button, otherwise the click action
			// on the WorkspaceTHumbClone will act weirdly
			close_button.button_press_event.connect (() => {
				closing ();
				return true;
			});

			add_child (close_button);

			var click = new ClickAction ();
			click.clicked.connect (() => selected ());
			add_action (click);
		}

		~DeepinWorkspaceThumbCloneCore ()
		{
			workspace.get_screen ().monitors_changed.disconnect (update_workspace_shadow);
			background.destroy ();
		}

		public override bool enter_event (CrossingEvent event)
		{
			// don't display the close button when we have dynamic workspaces or when there is only
			// one workspace
			if (Prefs.get_dynamic_workspaces () || Prefs.get_num_workspaces () == 1) {
				show_close_button (false);
			} else {
				show_close_button (true);
			}

			return false;
		}

		public override bool leave_event (CrossingEvent event)
		{
			show_close_button (false);
			return false;
		}

		void show_close_button (bool show)
		{
			close_button.save_easing_state ();

			close_button.set_easing_duration (300);
			close_button.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);

			if (show) {
				close_button.opacity = 255;
			} else {
				close_button.opacity = 0;
			}

			close_button.restore_easing_state ();
		}

		public void set_select (bool value, bool animate = true)
		{
			int duration = animate ? DeepinMultitaskingView.WORKSPACE_SWITCH_DURATION : 0;

			// selected shape for workspace thumbnail clone
			thumb_shape.save_easing_state ();

			thumb_shape.set_easing_duration (duration);
			thumb_shape.set_easing_mode (DeepinWorkspaceNameField.SELECT_MODE);// TODO:
			thumb_shape.opacity = value ? 255 : 0;

			thumb_shape.restore_easing_state ();
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
				DeepinWorkspaceThumbContainer.WORKSPACE_WIDTH_PERCENT);
		}

		int get_thumb_workspace_prefer_heigth ()
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
			return (int)(monitor_geom.height *
				DeepinWorkspaceThumbContainer.WORKSPACE_WIDTH_PERCENT);
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());

			// calculate ratio for monitor width and height
			float monitor_whr = (float)monitor_geom.height / monitor_geom.width;

			// allocate workspace clone
			var thumb_box = ActorBox ();
			float thumb_width = box.get_width ();
			float thumb_height = thumb_width * monitor_whr;
			thumb_box.set_size (thumb_width, thumb_height);
			thumb_box.set_origin (0, 0);
			workspace_clone.allocate (thumb_box, flags);
			workspace_shadow.allocate (thumb_box, flags);
			window_container.allocate (thumb_box, flags);

			// scale background
			float scale =
				box.get_width () != 0 ? box.get_width () / (float)monitor_geom.width : 0.5f;
			background.set_scale (scale, scale);

			var thumb_shape_box = ActorBox ();
			thumb_shape_box.set_size (
				thumb_width + THUMB_SHAPE_PADDING * 2, thumb_height + THUMB_SHAPE_PADDING * 2);
			thumb_shape_box.set_origin (
				(box.get_width () - thumb_shape_box.get_width ()) / 2, -THUMB_SHAPE_PADDING);
			thumb_shape.allocate (thumb_shape_box, flags);

			var close_box = ActorBox ();
			close_box.set_size (close_button.width, close_button.height);

			Granite.CloseButtonPosition pos;
			Granite.Widgets.Utils.get_default_close_button_position (out pos);
			switch (pos) {
			case Granite.CloseButtonPosition.RIGHT:
				close_box.set_origin (box.get_width () - close_box.get_width () * 0.60f,
									  -close_button.height * 0.40f);
				break;
			case Granite.CloseButtonPosition.LEFT:
				close_box.set_origin (-close_box.get_width () * 0.60f,
									  -close_button.height * 0.40f);
				break;
			}

			close_button.allocate (close_box, flags);
		}
	}

	/**
	 * Workspace name field which used to show and edit workspace names.
	 */
	public class DeepinWorkspaceNameField : Actor
	{
		public const int SELECT_DURATION = 500;
		public const AnimationMode SELECT_MODE = AnimationMode.LINEAR;

		public const int WORKSPACE_NAME_WIDTH = 70;
		public const int WORKSPACE_NAME_HEIGHT = 24;

		const int WORKSPACE_NAME_MAX_LENGTH = 32;

		const int NAME_SHAPE_PADDING = 5;

		// layout spacing for workspace name field
		const int WORKSPACE_NAME_SPACING = 5;

		public signal void selected ();

		public Workspace workspace { get; construct; }

		public Actor? fallback_key_focus = null;

		Actor workspace_name;
		Text workspace_name_num;
		Text workspace_name_text;
		int workspace_name_width;
		int workspace_name_height;

		// selected shape for workspace name field
		DeepinCssActor name_shape;

		public DeepinWorkspaceNameField (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			// selected shape for workspace name field
			name_shape = new DeepinCssActor ("deepin-workspace-thumb-clone-name");
			name_shape.reactive = true;
			name_shape.set_pivot_point (0.5f, 0.5f);

			name_shape.button_press_event.connect (on_name_button_press_event);

			add_child (name_shape);

			// workspace name field
			workspace_name = new Actor ();
			workspace_name.layout_manager = new BoxLayout ();

			var name_font = DeepinUtils.get_css_font ("deepin-workspace-thumb-clone-name");

			workspace_name_num = new Text ();
			workspace_name_num.set_font_description (name_font);

			workspace_name_text = new Text ();
			workspace_name_text.reactive = true;
			workspace_name_text.activatable = true;
			workspace_name_text.cursor_size = 1;
			workspace_name_text.ellipsize = Pango.EllipsizeMode.END;
			workspace_name_text.max_length = WORKSPACE_NAME_MAX_LENGTH;
			workspace_name_text.single_line_mode = true;
			workspace_name_text.set_font_description (name_font);
			workspace_name_text.selection_color =
				DeepinUtils.get_css_background_color ("deepin-text-selection");
			workspace_name_text.selected_text_color =
				DeepinUtils.get_css_color ("deepin-text-selection");

			workspace_name_text.button_press_event.connect (on_name_button_press_event);
			workspace_name_text.activate.connect (() => {
				reset_key_focus ();
				workspace_name_text.editable = false;
			});
			workspace_name_text.key_focus_in.connect (() => {
				if (workspace_name_text.text.length == 0) {
					workspace_name_text.visible = true;
				}
			});
			workspace_name_text.key_focus_out.connect (() => {
				set_workspace_name ();
				if (workspace_name_text.text.length == 0) {
					workspace_name_text.visible = false;
				}
			});

			get_workspace_name ();
			if (workspace_name_text.text.length == 0) {
				workspace_name_text.visible = false;
			}

			workspace_name.add_child (workspace_name_num);
			workspace_name.add_child (workspace_name_text);

			add_child (workspace_name);
		}

		bool on_name_button_press_event ()
		{
			if (workspace_name_text.editable && workspace_name_text.has_key_focus ()) {
				return false;
			}

			grab_key_focus_for_name ();

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
			// TODO: ask for workspace name format, dot
			workspace_name_num.text = "%d".printf (workspace.index () + 1);
			workspace_name_text.text = DeepinUtils.get_workspace_name (workspace.index ());
		}

		public void set_select (bool value, bool animate = true)
		{
			int duration = animate ? DeepinMultitaskingView.WORKSPACE_SWITCH_DURATION : 0;

			// selected shape for workspace name field
			name_shape.save_easing_state ();

			name_shape.set_easing_duration (duration);
			name_shape.set_easing_mode (SELECT_MODE);
			name_shape.select = value;

			if (value) {
				name_shape.scale_x = 1.1;
				name_shape.scale_y = 1.1;
			} else {
				name_shape.scale_x = 1.0;
				name_shape.scale_y = 1.0;
			}

			name_shape.restore_easing_state ();

			// font color for workspace name field
			workspace_name_num.save_easing_state ();
			workspace_name_text.save_easing_state ();

			workspace_name_num.set_easing_duration (duration);
			workspace_name_text.set_easing_duration (duration);

			workspace_name_num.set_easing_mode (SELECT_MODE);
			workspace_name_text.set_easing_mode (SELECT_MODE);

			var text_color = DeepinUtils.get_css_color ("deepin-workspace-thumb-clone-name",
				value ? Gtk.StateFlags.SELECTED : Gtk.StateFlags.NORMAL);
			workspace_name_num.color = text_color;
			workspace_name_text.color = text_color;

			workspace_name_num.restore_easing_state ();
			workspace_name_text.restore_easing_state ();
		}

		public void reset_key_focus ()
		{
			get_stage ().set_key_focus (fallback_key_focus);
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var name_shape_box = ActorBox ();
			name_shape_box.set_size (box.get_width (), box.get_height ());
			name_shape_box.set_origin (0, 0);
			name_shape.allocate (name_shape_box, flags);

			var name_box = ActorBox ();
			name_box.set_size (
				Math.fminf (workspace_name.width, WORKSPACE_NAME_WIDTH - NAME_SHAPE_PADDING * 2),
				workspace_name.height);
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

	/**
	 * Workspace thumnail clone with background, normal windows and workspace name fileds.
	 */
	public class DeepinWorkspaceThumbClone : Actor
	{
		// distance between thumbnail workspace clone and workspace name field
		public const int WORKSPACE_NAME_DISTANCE = 16;

		// TODO: duration
		const int FADE_DURATION = 1300;

		public signal void selected ();

		public Workspace workspace { get; construct; }

		public DeepinWindowThumbContainer window_container;

		public DeepinWorkspaceThumbCloneCore thumb_clone;

		public DeepinWorkspaceNameField workspace_name;

		public DeepinWorkspaceThumbClone (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			thumb_clone = new DeepinWorkspaceThumbCloneCore (workspace);
			thumb_clone.opacity = 0;
			window_container = thumb_clone.window_container;

			thumb_clone.selected.connect (() => selected ());

			add_child (thumb_clone);

			workspace_name = new DeepinWorkspaceNameField (workspace);
			workspace_name.opacity = 0;

			// TODO: select current workspace if workspace name is clicked
			// workspace_name.selected.connect (() => selected ());

			add_child (workspace_name);

			// Ensure workspace name field lost focus to avoid invalid operations even though the
			// workspace already not exists.
			thumb_clone.closing.connect (remove_workspace);
		}


		/*
		 * Remove current workspace and moving all the windows to preview workspace.
		 */
		public void remove_workspace ()
		{
			if (Prefs.get_num_workspaces () <= 1) {
				// there is only one workspace, just ignore
				return;
			}

			workspace_name.reset_key_focus ();

			DeepinUtils.start_fade_out_animation (
				this,
				DeepinWorkspaceThumbContainer.CHILD_FADE_DURATION,
				DeepinWorkspaceThumbContainer.CHILD_FADE_MODE,
				() => DeepinUtils.remove_workspace (workspace.get_screen (), workspace));
		}

		public void set_select (bool value, bool animate = true)
		{
			thumb_clone.set_select (value, animate);
			workspace_name.set_select (value, animate);
		}

		public void start_fade_in_animation ()
		{
			// TODO 85%time, 1.3s duration
			DeepinUtils.start_fade_in_back_animation (
				thumb_clone, FADE_DURATION,
				() => DeepinUtils.start_fade_in_back_animation (workspace_name,
																(int) (FADE_DURATION * 0.4)),
				0.6);
		}

		public void start_bulge_animation ()
		{
			// TODO: ask for animation, thumbnail bulge
			var transgroup = new TransitionGroup ();

			double[] keyframes = { 0.25, 0.75 };
			GLib.Value[] values = { 1.05f, 1.05f };
			// TODO:
			int duration = 500;
			// int duration = DeepinWindowClone.LAYOUT_DURATION;

			var transition = new KeyframeTransition ("scale-x");
			transition.set_duration (duration);
			transition.set_progress_mode (AnimationMode.EASE_IN_BACK);
			transition.set_from_value (1.0f);
			transition.set_to_value (1.0f);
			transition.set_key_frames (keyframes);
			transition.set_values (values);
			transgroup.add_transition (transition);

			transition = new KeyframeTransition ("scale-y");
			transition.set_duration (duration);
			transition.set_progress_mode (AnimationMode.EASE_IN_BACK);
			transition.set_from_value (1.0f);
			transition.set_to_value (1.0f);
			transition.set_key_frames (keyframes);
			transition.set_values (values);
			transgroup.add_transition (transition);

			transgroup.set_duration (duration);
			transgroup.remove_on_complete = true;

			if (thumb_clone.get_transition ("bulge") != null) {
				thumb_clone.remove_transition ("bulge");
			}
			thumb_clone.add_transition ("bulge", transgroup);
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());

			// calculate ratio for monitor width and height
			float monitor_whr = (float)monitor_geom.height / monitor_geom.width;

			// allocate workspace clone
			var thumb_box = ActorBox ();
			float thumb_width = box.get_width ();
			float thumb_height = thumb_width * monitor_whr;
			thumb_box.set_size (thumb_width, thumb_height);
			thumb_box.set_origin (0, 0);
			thumb_clone.allocate (thumb_box, flags);

			// allocate workspace name field
			var name_box = ActorBox ();
			name_box.set_size (DeepinWorkspaceNameField.WORKSPACE_NAME_WIDTH,
							   DeepinWorkspaceNameField.WORKSPACE_NAME_HEIGHT);
			name_box.set_origin ((box.get_width () - name_box.get_width ()) / 2,
								 thumb_box.y2 + WORKSPACE_NAME_DISTANCE);
			workspace_name.allocate (name_box, flags);
		}
	}
}
