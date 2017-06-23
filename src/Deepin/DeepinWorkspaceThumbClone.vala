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
		Actor thumb_shape_selected;

		Actor workspace_shadow;
		Actor workspace_clone;

		DeepinFramedBackground background;

		DeepinIconActor close_button;

		public DeepinWorkspaceThumbCloneCore (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			workspace_shadow = new Actor ();
			workspace_shadow.add_effect_with_name (
				"shadow", new ShadowEffect (get_thumb_workspace_prefer_width (),
											get_thumb_workspace_prefer_heigth (), 10, 0, 26, 3));
            add_child (workspace_shadow);

			workspace.get_screen ().monitors_changed.connect (update_workspace_shadow);

            thumb_shape =
                new DeepinCssStaticActor ("deepin-workspace-thumb-clone", Gtk.StateFlags.NORMAL);
            thumb_shape.set_pivot_point (0.5f, 0.5f);

            // selected shape for workspace thumbnail clone
            thumb_shape_selected =
                new DeepinCssStaticActor ("deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
            thumb_shape_selected.opacity = 0;
            thumb_shape_selected.set_pivot_point (0.5f, 0.5f);

			// workspace thumbnail clone
			workspace_clone = new Actor ();
			workspace_clone.set_pivot_point (0.5f, 0.5f);

			// size-scaled background
			background = new DeepinFramedBackground (workspace.get_screen (),
													 workspace.index (), false, false, 
                                                     DeepinWorkspaceThumbContainer.WORKSPACE_WIDTH_PERCENT);
			background.button_press_event.connect (() => {
				selected ();
				return true;
			});
            background.set_rounded_radius (6);
			workspace_clone.add_child (background);

			window_container = new DeepinWindowThumbContainer (workspace);
            window_container.clip_to_allocation = true;
			window_container.window_activated.connect ((w) => selected ());
			window_container.window_dragging.connect ((w) => {
				// If window is dragging in thumbnail workspace, make close button manually or it
				// will keep shown only mouse move in and out again.
				show_close_button (false);
			});
			workspace_clone.add_child (window_container);

            add_child (thumb_shape);
			add_child (workspace_clone);
            add_child (thumb_shape_selected);

			// close button
            close_button = new DeepinIconActor ("close");
			close_button.opacity = 0;
			close_button.released.connect (() => {
				closing ();
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

            window_container.splay_windows ();
			return false;
		}

		public override bool leave_event (CrossingEvent event)
		{
			show_close_button (false);
            window_container.relayout ();
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

            thumb_shape.visible = !value;

			// selected shape for workspace thumbnail clone
            thumb_shape_selected.save_easing_state ();

            thumb_shape_selected.set_easing_duration (duration);
            thumb_shape_selected.set_easing_mode (AnimationMode.LINEAR);
            thumb_shape_selected.opacity = value ? 255 : 0;

            thumb_shape_selected.restore_easing_state ();

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

			// allocate workspace clone
			var thumb_box = ActorBox ();
			float thumb_width = Math.floorf(box.get_width ());
			float thumb_height = Math.floorf(box.get_height ());
			thumb_box.set_size (thumb_width, thumb_height);
			thumb_box.set_origin (0, 0);
			workspace_clone.allocate (thumb_box, flags);
			workspace_shadow.allocate (thumb_box, flags);
			window_container.allocate (thumb_box, flags);

            background.set_size (thumb_width, thumb_height);

			var thumb_shape_box = ActorBox ();
			thumb_shape_box.set_size (thumb_width+2, thumb_height+2);
			thumb_shape_box.set_origin (-1, -1);
            thumb_shape.allocate (thumb_shape_box, flags);

            thumb_shape_box.set_size (thumb_width+6, thumb_height+6);
            thumb_shape_box.set_origin (-3, -3);
            thumb_shape_selected.allocate (thumb_shape_box, flags);

            var close_box = ActorBox ();
            close_box.set_size (close_button.width, close_button.height);
            close_box.set_origin (box.get_width () - close_box.get_width () * 0.50f,
                                  -close_button.height * 0.50f);
            close_button.allocate (close_box, flags);
		}
	}


	/**
	 * Provide help message when dragging to remove workspace.
	 */
	public class DeepinWorkspaceThumbRemoveTip : DeepinCssStaticActor
	{
		public const float POSITION_PERCENT = 0.449f;
		public const float MESSAGE_PERCENT = 0.572f;
		public const float LINE_START = 0.060f;

		const double LINE_WIDTH = 0.5;

		Gdk.RGBA color;
		Text message;
        Clutter.Actor icon;

		public DeepinWorkspaceThumbRemoveTip ()
		{
			base ("deepin-workspace-thumb-remove-tip");
		}

		construct
		{
			color = DeepinUtils.get_css_color_gdk_rgba (style_class);

			(content as Canvas).draw.connect (on_draw_content);

			var name_font = DeepinUtils.get_css_font ("deepin-workspace-thumb-remove-tip");

			message = new Text ();
			message.set_font_description (name_font);
			message.color = DeepinUtils.gdkrgba2color (color);
			message.text = (_("Drag upwards to remove"));
			add_child (message);

            icon = new Clutter.Actor ();

            var pixbuf = new Gdk.Pixbuf.from_file (Config.PKGDATADIR + "/path.svg");
            var image = new Clutter.Image ();

            image.set_data (pixbuf.get_pixels (),
                    pixbuf.get_has_alpha () ? Cogl.PixelFormat.RGBA_8888 : Cogl.PixelFormat.RGB_888,
                    pixbuf.get_width (),
                    pixbuf.get_height (),
                    pixbuf.get_rowstride ());

            icon.content = image;
            icon.set_size (pixbuf.get_width (), pixbuf.get_height ());
            icon.set_position (0, 0);
            add_child (icon);
		}

		bool on_draw_content (Cairo.Context cr, int width, int height)
		{
			// draw dash line
			cr.move_to (width * LINE_START, height * POSITION_PERCENT);
			cr.line_to (width * (1.0f - 2.0f * LINE_START), height * POSITION_PERCENT);

			cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
			cr.set_line_width (LINE_WIDTH);
			cr.set_dash ({5.0, 3.0}, 1);
			cr.stroke ();

			return false;
		}

		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

            var total = message.width + icon.width + 9;
			var icon_x = (box.get_width () - total)/2;
            var msg_x = icon_x + icon.width + 9;

            var icon_y = box.get_height () * MESSAGE_PERCENT + message.height/2 - icon.height/2;

			// allocate workspace clone
			var message_box = ActorBox ();
			message_box.set_size (message.width, message.height);
			message_box.set_origin (msg_x, box.get_height () * MESSAGE_PERCENT);
			message.allocate (message_box, flags);

			var icon_box = ActorBox ();
			icon_box.set_size (icon.width, icon.height);
			icon_box.set_origin (icon_x, icon_y);
            icon.allocate (icon_box, flags);
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

        enum DragOperation {
            NULL = 0,
            DRAG_TO_REMOVE = 1,
            DRAG_TO_SWITCH = 2
        }


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
			drag_action.allow_direction = DragDropActionDirection.ALL & ~DragDropActionDirection.DOWN;
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
				() => DeepinUtils.remove_workspace (workspace.get_screen (), workspace),
                0.6);
		}

		public void set_select (bool value, bool animate = true)
		{
			thumb_clone.set_select (value, animate);
		}

		public void start_fade_in_animation ()
        {
            var animation = new TransitionGroup ();
            animation.duration = DeepinMultitaskingView.WORKSPACE_FADE_DURATION + 50;
            animation.remove_on_complete = true;
            animation.progress_mode = DeepinMultitaskingView.WORKSPACE_FADE_MODE;

            GLib.Value[] scales = {0.0f, 1.0f};
            double[] keyframes = {0.0, 1.0};

            var opacity_transition = new PropertyTransition ("opacity");
            opacity_transition.set_from_value (0);
            opacity_transition.set_to_value (255);

            var scale_x_transition = new KeyframeTransition ("scale-x");
            scale_x_transition.set_from_value (0.0);
            scale_x_transition.set_to_value (1.0);
            scale_x_transition.set_key_frames (keyframes);
            scale_x_transition.set_values (scales);

            var scale_y_transition = new KeyframeTransition ("scale-y");
            scale_y_transition.set_from_value (0.0);
            scale_y_transition.set_to_value (1.0);
            scale_y_transition.set_key_frames (keyframes);
            scale_y_transition.set_values (scales);

            animation.add_transition (opacity_transition);
            animation.add_transition (scale_x_transition);
            animation.add_transition (scale_y_transition);

            thumb_clone.set_pivot_point (0.5f, 0.5f);
            thumb_clone.add_transition ("fade-in", animation);

            animation.stopped.connect(() => {
                thumb_clone.opacity = 255;
                thumb_clone.set_scale (1.0f, 1.0f);
            });
        }

		/**
		 * Enable drag action, should be called after relayout.
		 */
		public void enable_drag_action ()
		{
			drag_action.allow_direction = DragDropActionDirection.ALL & ~DragDropActionDirection.DOWN;
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

			// allocate workspace clone
			var thumb_box = ActorBox ();
			float thumb_width = Math.floorf(box.get_width ());
            float thumb_height = Math.floorf(box.get_height ());
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

        DragOperation current_op = DragOperation.NULL;
        ActorBox? drag_to_remove_box = null;

        // TODO: log previous indexes of each ws
		Actor on_drag_begin (float click_x, float click_y)
		{
			if (Prefs.get_num_workspaces () <= 1) {
				// there is only one workspace, just ignore
				return null;
			}

            current_op = DragOperation.NULL;
            drag_to_remove_box = null;

			Actor drag_actor = thumb_clone;

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

            // precalculate 
            get_drag_to_remove_area ();

			return drag_actor;
		}

        void toggle_remove_tip (bool show)
        {
            if (show && remove_tip.opacity == 255) {
                return;
            } else if (!show && remove_tip.opacity == 0) {
                return;
            }

            remove_tip.save_easing_state ();
            remove_tip.set_easing_duration (DRAG_MOVE_DURATION);
            remove_tip.opacity = show?255:0;
            remove_tip.restore_easing_state ();
        }

        ActorBox get_drag_to_remove_area()
		{
            if (drag_to_remove_box == null) {
                var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());

                var box = ActorBox ();

                float child_width = 0, child_height = 0;
                float child_spacing = monitor_geom.width * DeepinWorkspaceThumbContainer.SPACING_PERCENT;
                float allowed_height = monitor_geom.height * DeepinMultitaskingView.FLOW_WORKSPACE_TOP_OFFSET_PERCENT;
                float abs_x, abs_y;

                get_transformed_position (out abs_x, out abs_y);

                DeepinWorkspaceThumbContainer.get_prefer_thumb_size (workspace.get_screen (),
                        out child_width, out child_height);
                box.set_size ((child_width + child_spacing) * 2.0f, allowed_height);
                box.set_origin (abs_x - child_spacing - child_width / 2.0f, 0.0f);

                drag_action.allow_y_overflow = allowed_height - abs_y - child_height;
                drag_to_remove_box = box;
                //stderr.printf("drag_to_remove_area (%f, %f, %f, %f)\n", box.x1, box.y1, box.x2-box.x1, box.y2-box.y1);
            }
			return drag_to_remove_box;
		}

        DragOperation get_drag_operation()
        {
			Actor drag_actor = thumb_clone;

			float tip_height = drag_actor.height *
				(1 - DeepinWorkspaceThumbRemoveTip.POSITION_PERCENT);

            if (current_op == DragOperation.DRAG_TO_SWITCH) {
                return current_op;
            }
            var box = get_drag_to_remove_area ();

            unowned Clutter.Event ev = Clutter.get_current_event ();
            float x, y;
            ev.get_coords (out x, out y);

            if (box.contains (x, y)) {

                current_op = DragOperation.DRAG_TO_REMOVE;
            } else {
                current_op = DragOperation.DRAG_TO_SWITCH;
            }

            return current_op;
        }

		void on_drag_motion (float delta_x, float delta_y)
		{
			Actor drag_actor = thumb_clone;

			// hiding thumbnail after dragging crossed the remove tip
			float tip_height = drag_actor.height *
				(1 - DeepinWorkspaceThumbRemoveTip.POSITION_PERCENT);
			float refer_height = drag_actor.height - tip_height;

            var op = get_drag_operation();

            delta_y = Math.fabsf (delta_y);
            switch (op) {
                case DragOperation.DRAG_TO_REMOVE:
                    if (delta_y <= tip_height) {
                        current_op = DragOperation.NULL;

                        drag_actor.save_easing_state ();
                        drag_actor.set_easing_duration (DRAG_MOVE_DURATION);
                        drag_actor.opacity = 255;
                        drag_actor.restore_easing_state ();

                        toggle_remove_tip (false);
                    } else {
                        delta_y -= tip_height;
                        uint opacity = 255 - (uint)(delta_y / refer_height * 200);
                        drag_actor.opacity = opacity;
                        toggle_remove_tip (true);
                    }
                    break;

                case DragOperation.DRAG_TO_SWITCH:
                    unowned Clutter.Event ev = Clutter.get_current_event ();
                    float x, y;
                    ev.get_coords (out x, out y);

                    if (remove_tip.opacity != 0) {
                        drag_actor.save_easing_state ();
                        drag_actor.set_easing_duration (DRAG_MOVE_DURATION);
                        drag_actor.opacity = 255;
                        drag_actor.restore_easing_state ();

                        toggle_remove_tip (false);
                    }

                    Actor current_switching_target = null;
                    var cntr = get_parent () as DeepinWorkspaceThumbContainer;
                    foreach (var actor in cntr.get_children ()) {
                        if (!(actor is DeepinWorkspaceThumbClone))
                            continue;

                        if (actor == this) continue;

                        var box = ActorBox ();
                        float w, h;
                        actor.get_transformed_position (out box.x1, out box.y1);
                        actor.get_transformed_size (out w, out h);
                        box.set_size (w, h);

                        if (box.contains (x, y)) {
                            current_switching_target = actor;
                            break;
                        }
                    }

                    if (current_switching_target != null) {
                        if (current_switching_target.get_data<bool>("switching") != true) {
                            current_switching_target.set_data<bool>("switching", true);
                            cntr.start_reorder_workspace(this, current_switching_target);

                            current_switching_target.transition_stopped.connect((name, finished) => {
                                if (name == "thumb-workspace-slot") {
                                    current_switching_target.set_data<bool>("switching", false);
                                }
                            });
                        }
                    }
                    break;

                default:
                    break;
            }
		}

		/**
		 * Remove current workpsace if drag crossed remove-tip or restore it.
		 */
		void on_drag_canceled ()
		{
			Actor drag_actor = thumb_clone;

			if (current_op == DragOperation.DRAG_TO_REMOVE) {
				// remove current workspace

				closing ();
                toggle_remove_tip (false);

				drag_actor.save_easing_state ();
				drag_actor.set_easing_duration (DeepinMultitaskingView.WORKSPACE_FADE_DURATION);
				drag_actor.opacity = 0;
				drag_actor.y -= drag_actor.height;
				drag_actor.restore_easing_state ();

				DeepinUtils.run_clutter_callback (drag_actor, "opacity", () => {
					DeepinUtils.remove_workspace (workspace.get_screen (), workspace);
				});
			} else if (current_op == DragOperation.DRAG_TO_SWITCH) {

				(drag_actor as DeepinWorkspaceThumbCloneCore).show_close_button (false);
                Idle.add (() => {
                    do_drag_restore ();
                    return false;
                });

                do_real_workspaces_reorder ();
			} else {
				(drag_actor as DeepinWorkspaceThumbCloneCore).show_close_button (false);
                Idle.add (() => {
                    do_drag_restore ();
                    return false;
                });
            }

            current_op = DragOperation.NULL;
            drag_to_remove_box = null;
		}

        void do_real_workspaces_reorder ()
        {
			var i = 0;
            var cntr = get_parent () as DeepinWorkspaceThumbContainer;
			foreach (var child in cntr.get_children ()) {
                if (child == this) {
                    break;
                }
                i++;
			}

            //stderr.printf("switch done, do real switch from %d -> %d\n", workspace.index (), i);
            var p = get_parent ().get_parent ();
            var mt = (p as DeepinMultitaskingView);
            mt.reorder_workspace(workspace, i);
        }

		void do_drag_restore ()
		{
			Actor drag_actor = thumb_clone;
            drag_actor.opacity = 255;
			DeepinUtils.clutter_actor_reparent (drag_actor, this);
			this.set_child_at_index (drag_actor, drag_prev_index);
			queue_relayout ();
		}
	}
}
