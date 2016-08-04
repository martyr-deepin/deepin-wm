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
			thumb_shape.set_easing_mode (AnimationMode.LINEAR);
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
			message.text = (_("Drag upwards to remove"));
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

			DeepinUtils.start_fade_out_animation (
				this,
				DeepinMultitaskingView.WORKSPACE_FADE_DURATION,
				DeepinMultitaskingView.WORKSPACE_FADE_MODE,
				() => DeepinUtils.remove_workspace (workspace.get_screen (), workspace));
		}

		public void set_select (bool value, bool animate = true)
		{
			thumb_clone.set_select (value, animate);
		}

		public void start_fade_in_animation ()
		{
			DeepinUtils.start_fade_in_back_animation (thumb_clone, FADE_IN_DURATION);
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
			if (Prefs.get_num_workspaces () <= 1) {
				// there is only one workspace, just ignore
				return null;
			}

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
