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

		public Actor background;

		Actor close_button;

		// The DeepinRoundRectEffect works bad, so we drawing the outline to make it looks
		// antialise, but the drawing color is different for normal and selected state, so we must
		// update it manually.
		Gdk.RGBA roundRectColorNormal;
		Gdk.RGBA roundRectColorSelected;
		DeepinRoundRectOutlineEffect roundRectOutlineEffect;

		public DeepinWorkspaceThumbCloneCore (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			// workspace shadow effect, angle:90°, size:5, distance:1, opacity:30%
			workspace_shadow = new Actor ();
			workspace_shadow.add_effect_with_name (
				"shadow", new ShadowEffect (get_thumb_workspace_prefer_width (),
											get_thumb_workspace_prefer_heigth (), 10, 1, 76));
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

			// setup rounded rectangle effect
			int radius = DeepinUtils.get_css_border_radius (
				"deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
			roundRectColorNormal = DeepinUtils.get_css_background_color_gdk_rgba (
				"deepin-window-manager");
			roundRectColorSelected = DeepinUtils.get_css_background_color_gdk_rgba (
				"deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
			roundRectOutlineEffect =
				new DeepinRoundRectOutlineEffect ((int)width, (int)height, radius,
												  roundRectColorNormal);
			workspace_clone.add_effect (roundRectOutlineEffect);
			workspace_clone.add_effect (new DeepinRoundRectEffect (radius));

			background = new DeepinFramedBackground (workspace.get_screen (),
													 workspace.index (), false);
			background.button_press_event.connect (() => {
				selected ();
				return true;
			});
			workspace_clone.add_child (background);

			window_container = new DeepinWindowThumbContainer (workspace);
			window_container.window_activated.connect ((w) => selected ());
			window_container.window_dragging.connect ((w) => {
				// If window is dragging in thumbnail workspace, make close button manually or it
				// will keep shown only mouse move in and out again.
				show_close_button (false);
			});
			workspace_clone.add_child (window_container);

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

		public void show_close_button (bool show)
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
			thumb_shape.set_easing_mode (DeepinWorkspaceNameField.SELECT_MODE);
			thumb_shape.opacity = value ? 255 : 0;

			thumb_shape.restore_easing_state ();

			// update the outline fixing color for rounded rectangle effect
			if (value) {
				roundRectOutlineEffect.update_color (roundRectColorSelected);
			} else {
				roundRectOutlineEffect.update_color (roundRectColorNormal);
			}
			queue_redraw ();
		}

		void update_workspace_shadow ()
		{
			var shadow_effect = workspace_shadow.get_effect ("shadow") as ShadowEffect;
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

		const int NAME_SHAPE_PADDING = 4;

		// layout spacing for workspace name field
		const int WORKSPACE_NAME_SPACING = 5;

		public signal void selected ();

		/**
		 * Send setup_completed signal only when finish edit new added workpsace name.
		 */
		public signal void setup_completed (bool complete);

		public Workspace workspace { get; construct; }

		public Actor? fallback_key_focus = null;

		Actor workspace_name;
		Text workspace_name_num;
		DeepinIMText?  workspace_name_text;

		// selected shape for workspace name field
		DeepinCssActor name_shape;

		bool first_setup = true;
        uint event_filter_id = 0;

		public DeepinWorkspaceNameField (Workspace workspace)
		{
			Object (workspace: workspace);
		}
        
        bool event_filter(Clutter.Event ev) {
            Meta.verbose ("event_filter\n");
            if (workspace_name_text == null 
                    || !workspace_name_text.has_key_focus ()) 
                return false;

            if (ev.get_type () == Clutter.EventType.BUTTON_PRESS) {
                if (ev.get_device ().get_pointer_actor () !=
                        workspace_name_text) {
                    Meta.verbose ("event_filter: click outside\n");
                    workspace_name_text.activate ();
                }
            }

            return false;
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

			workspace_name_text = new DeepinIMText (workspace.get_screen ());
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

            bool is_completed = false;


            workspace_name_text.button_press_event.connect (on_name_button_press_event);

			workspace_name_text.activate.connect (() => {
                finish_edit ();
                is_completed = true;
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

				notify_setup_completed_if_need (is_completed);
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
            Meta.verbose ("%s\n", Log.METHOD);
			if (workspace_name_text.editable && workspace_name_text.has_key_focus ()) {
				return false;
			}

			start_edit ();

			selected ();

			// Return false to let event continue to be passed, so the cursor will be put in the
			// position of the mouse.
			return false;
		}

		/**
		 * Notify setup_completed signal if workspace name is set for new workspace.
		 */
		void notify_setup_completed_if_need (bool complete)
		{
			if (first_setup) {
				first_setup = false;
				setup_completed (complete);
			}
		}

		public void start_edit ()
        {
            workspace_name_text.editable = true;
            workspace_name_text.grab_key_focus ();

            event_filter_id = (uint) get_stage ().captured_event.connect (event_filter);
        }

		public void finish_edit ()
		{
            if (event_filter_id > 0) {
                SignalHandler.disconnect (get_stage (), event_filter_id);
            }

			reset_key_focus ();
			workspace_name_text.editable = false;
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

			// place Text actors with offset to make it looks in the middle
			int text_y_offset = 1;

			var name_box = ActorBox ();
			name_box.set_size (
				Math.fminf (workspace_name.width, WORKSPACE_NAME_WIDTH - NAME_SHAPE_PADDING * 2),
				WORKSPACE_NAME_HEIGHT);
			name_box.set_origin (
				(box.get_width () - name_box.get_width ()) / 2,
				text_y_offset + name_shape_box.y1 +
					(name_shape_box.get_height () - name_box.get_height ()) / 2);
			workspace_name.allocate (name_box, flags);

			// update layout for workspace name field
			var name_layout = workspace_name.layout_manager as BoxLayout;
			if (workspace_name_text.text.length > 0 || workspace_name_text.editable) {
				name_layout.spacing = WORKSPACE_NAME_SPACING;
			} else {
				name_layout.spacing = 0;
			}
		}
	}

	/**
	 * Provide help message when dragging to remove workspace.
	 */
	public class DeepinWorkspaceThumbRemoveTip : DeepinCssStaticActor
	{
		public const float POSITION_PERCENT = 0.66f;

		const double LINE_WIDTH = 3.0;

		Gdk.RGBA color;
		Text message;

		public DeepinWorkspaceThumbRemoveTip ()
		{
			base ("deepin-workspace-thumb-remove-tip");
		}

		construct
		{
			color = DeepinUtils.get_css_color_gdk_rgba (style_class);

			(content as Canvas).draw.connect (on_draw_content);

			var name_font = DeepinUtils.get_css_font ("deepin-workspace-thumb-clone-name");

			message = new Text ();
			message.set_font_description (name_font);
			message.color = DeepinUtils.gdkrgba2color (color);
			message.text = (_("Drag upward to remove"));
			add_child (message);
		}

		bool on_draw_content (Cairo.Context cr, int width, int height)
		{
			// draw dash line
			cr.move_to (0, height * POSITION_PERCENT);
			cr.line_to (width, height * POSITION_PERCENT);

			cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
			cr.set_line_width (LINE_WIDTH);
			cr.set_dash ({12.0, 8.0}, 1);
			cr.stroke ();

			return false;
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			// allocate workspace clone
			var message_box = ActorBox ();
			message_box.set_size (message.width, message.height);
			message_box.set_origin ((box.get_width () - message_box.get_width ()) / 2, box.get_height () * POSITION_PERCENT + 6);
			message.allocate (message_box, flags);
		}
	}

	/**
	 * Workspace thumnail clone with background, normal windows and workspace name fileds.
	 */
	public class DeepinWorkspaceThumbClone : Actor
	{
		// distance between thumbnail workspace clone and workspace name field
		public const int WORKSPACE_NAME_DISTANCE = 16;

		const int FADE_IN_DURATION = 1300;
		const int DRAG_BEGIN_DURATION = 400;
		const int DRAG_MOVE_DURATION = 100;
		const int DRAG_RESTORE_DURATION = 400;

		public signal void selected ();
		public signal void closing ();

		public Workspace workspace { get; construct; }

		public DeepinWindowThumbContainer window_container;
		public DeepinWorkspaceThumbCloneCore thumb_clone;
		public DeepinWorkspaceNameField workspace_name;

		Actor remove_tip;

		DragDropAction? drag_action = null;
		float drag_prev_x = 0;
		float drag_prev_y = 0;
		int drag_prev_index = -1;
		bool drag_to_remove = false;

		public DeepinWorkspaceThumbClone (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			remove_tip = new DeepinWorkspaceThumbRemoveTip ();
			remove_tip.opacity = 0;
			add_child (remove_tip);

			thumb_clone = new DeepinWorkspaceThumbCloneCore (workspace);
			thumb_clone.opacity = 0;
			thumb_clone.reactive = true;
			window_container = thumb_clone.window_container;

			thumb_clone.selected.connect (() => selected ());

			drag_action = new DragDropAction (DragDropActionType.SOURCE,
											  "deepin-workspace-thumb-clone");
			drag_action.allow_direction = DragDropActionDirection.UP;
			drag_action.actor_clicked.connect (on_actor_clicked);
			drag_action.drag_begin.connect (on_drag_begin);
			drag_action.drag_motion.connect (on_drag_motion);
			drag_action.drag_canceled.connect (on_drag_canceled);
			thumb_clone.add_action (drag_action);

			add_child (thumb_clone);

			workspace_name = new DeepinWorkspaceNameField (workspace);
			workspace_name.opacity = 0;

			add_child (workspace_name);

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

			closing ();

			// Ensure workspace name field lost focus to avoid invalid operations even though the
			// workspace already not exists.
			workspace_name.reset_key_focus ();

			DeepinUtils.start_fade_out_animation (
				this,
				DeepinMultitaskingView.WORKSPACE_FADE_DURATION,
				DeepinMultitaskingView.WORKSPACE_FADE_MODE,
				() => DeepinUtils.remove_workspace (workspace.get_screen (), workspace));
		}

		public void set_select (bool value, bool animate = true)
		{
			thumb_clone.set_select (value, animate);
			workspace_name.set_select (value, animate);
		}

		public void start_fade_in_animation ()
		{
			DeepinUtils.start_fade_in_back_animation (
				thumb_clone, FADE_IN_DURATION,
				() =>  {
					DeepinUtils.start_fade_in_back_animation (workspace_name,
															  (int) (FADE_IN_DURATION * 0.4));
				},
				0.6);
		}

		/**
		 * Enable drag action, should be called after relayout.
		 */
		public void enable_drag_action ()
		{
			drag_action.allow_direction = DragDropActionDirection.UP;
		}

		/**
		 * Disable drag action, should be called before relayout, include new workspace adding and
		 * removing.
		 */
		public void disable_drag_action ()
		{
			drag_action.allow_direction = DragDropActionDirection.NONE;
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
			remove_tip.allocate (thumb_box, flags);

			// allocate workspace name field
			var name_box = ActorBox ();
			name_box.set_size (DeepinWorkspaceNameField.WORKSPACE_NAME_WIDTH,
							   DeepinWorkspaceNameField.WORKSPACE_NAME_HEIGHT);
			name_box.set_origin ((box.get_width () - name_box.get_width ()) / 2,
								 thumb_box.y2 + WORKSPACE_NAME_DISTANCE);
			workspace_name.allocate (name_box, flags);
		}

		void on_actor_clicked (uint32 button)
		{
			switch (button) {
			case 1:
				selected ();
				break;
			}
		}

		Actor on_drag_begin (float click_x, float click_y)
		{
			Actor drag_actor = thumb_clone;

			drag_to_remove = false;

			float abs_x, abs_y;
			float prev_width, prev_height;

			// get required information before reparent
			get_transformed_position (out abs_x, out abs_y);
			drag_prev_x = abs_x;
			drag_prev_y = abs_y;
			drag_prev_index = get_children ().index (drag_actor);
			prev_width = drag_actor.width;
			prev_height = drag_actor.height;

			if (!this.contains (drag_actor)) {
				// return null to abort the drag
				return null;
			}

			// reparent
			DeepinUtils.clutter_actor_reparent (drag_actor, get_stage ());

			drag_actor.set_size (prev_width, prev_height);
			drag_actor.set_position (abs_x, abs_y);

			remove_tip.opacity = 255;

			workspace_name.reset_key_focus ();
			DeepinUtils.start_fade_out_animation (
				workspace_name, DRAG_BEGIN_DURATION, DeepinMultitaskingView.WORKSPACE_FADE_MODE);

			return drag_actor;
		}

		void on_drag_motion (float delta_x, float delta_y)
		{
			Actor drag_actor = thumb_clone;

			// hiding thumbnail after dragging crossed the remove tip
			float tip_height = drag_actor.height *
				(1 - DeepinWorkspaceThumbRemoveTip.POSITION_PERCENT);
			float refer_height = drag_actor.height - tip_height;

			// "delta_y < 0" means dragging up
			if (delta_y < 0) {
				delta_y = Math.fabsf (delta_y);
				if (delta_y <= tip_height + 15) {
					drag_to_remove = false;

					drag_actor.save_easing_state ();
					drag_actor.set_easing_duration (DRAG_MOVE_DURATION);
					drag_actor.opacity = 255;
					drag_actor.restore_easing_state ();

					remove_tip.save_easing_state ();
					remove_tip.set_easing_duration (DRAG_MOVE_DURATION);
					remove_tip.opacity = 255;
					remove_tip.restore_easing_state ();
				} else {
					drag_to_remove = true;

					delta_y -= tip_height;
					if (delta_y >= refer_height) {
						delta_y = refer_height;
					}

					uint opacity = 255 - (uint)(delta_y / refer_height * 200);

					drag_actor.save_easing_state ();
					drag_actor.set_easing_duration (DRAG_MOVE_DURATION);
					drag_actor.opacity = opacity;
					drag_actor.restore_easing_state ();

					remove_tip.save_easing_state ();
					remove_tip.set_easing_duration (DRAG_MOVE_DURATION);
					remove_tip.opacity = opacity;
					remove_tip.restore_easing_state ();
				}
			}
		}

		/**
		 * Remove current workpsace if drag crossed remove tipe or restore it.
		 */
		void on_drag_canceled ()
		{
			Actor drag_actor = thumb_clone;

			if (drag_to_remove) {
				// remove current workspace

				closing ();

				remove_tip.save_easing_state ();
				remove_tip.set_easing_duration (DeepinMultitaskingView.WORKSPACE_FADE_DURATION);
				remove_tip.opacity = 0;
				remove_tip.restore_easing_state ();

				drag_actor.save_easing_state ();
				drag_actor.set_easing_duration (DeepinMultitaskingView.WORKSPACE_FADE_DURATION);
				drag_actor.opacity = 0;
				drag_actor.y -= drag_actor.height;
				drag_actor.restore_easing_state ();

				DeepinUtils.run_clutter_callback (drag_actor, "opacity", () => {
					DeepinUtils.remove_workspace (workspace.get_screen (), workspace);
				});
			} else {
				// restore state

				DeepinUtils.start_fade_in_animation (
					workspace_name, DRAG_RESTORE_DURATION,
					DeepinMultitaskingView.WORKSPACE_FADE_MODE);

				remove_tip.save_easing_state ();
				remove_tip.set_easing_duration (DRAG_RESTORE_DURATION);
				remove_tip.opacity = 0;
				remove_tip.restore_easing_state ();

				(drag_actor as DeepinWorkspaceThumbCloneCore).show_close_button (false);

				drag_actor.save_easing_state ();
				drag_actor.set_easing_duration (DRAG_RESTORE_DURATION);
				drag_actor.opacity = 255;
				drag_actor.x = drag_prev_x;
				drag_actor.y = drag_prev_y;
				drag_actor.restore_easing_state ();

				DeepinUtils.run_clutter_callback (drag_actor, "opacity", () => {
					// use Idle to split the inner callback or will panic for could not site
					// drag_actor correctly
					Idle.add (() => {
						do_drag_restore ();
						return false;
					});
				});
			}
		}
		void do_drag_restore ()
		{
			Actor drag_actor = thumb_clone;
			DeepinUtils.clutter_actor_reparent (drag_actor, this);
			this.set_child_at_index (drag_actor, drag_prev_index);
			queue_relayout ();
		}
	}
}
