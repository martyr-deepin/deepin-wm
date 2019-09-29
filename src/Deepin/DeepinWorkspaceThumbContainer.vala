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

using Clutter;
using Meta;

namespace Gala
{
	/**
	 * Will be put at end of workspace thumbnail list in DeepinMultitaskingView if number less than
	 * MAX_WORKSPACE_NUM.
	 */
	class DeepinWorkspaceAddButton : DeepinCssStaticActor
	{
		const double PLUS_SIZE = 45.0;
		const double PLUS_LINE_WIDTH = 2.0;

        private double scale_factor = 1.0;

		Gdk.RGBA color;

		public DeepinWorkspaceAddButton ()
		{
			base ("deepin-workspace-add-button");
		}

		construct
		{
			color = DeepinUtils.get_css_color_gdk_rgba (style_class);
            scale_factor = DeepinXSettings.get_default ().schema.get_double ("scale-factor");

			//(content as Canvas).draw.connect (on_draw_content);
		}

		protected override bool on_draw_content (Cairo.Context cr, int width, int height)
		{
			style_context.set_state (state);

            var plus_size = PLUS_SIZE * scale_factor;

            cr.set_operator (Cairo.Operator.SOURCE);
            style_context.render_background (cr, 0, 0, width, height);
            cr.set_operator (Cairo.Operator.OVER);
            style_context.render_frame (cr, 0, 0, width, height);

			// draw tha plus button
			cr.move_to (width / 2 - plus_size / 2, height / 2);
			cr.line_to (width / 2 + plus_size / 2, height / 2);

			cr.move_to (width / 2, height / 2 - plus_size / 2);
			cr.line_to (width / 2, height / 2 + plus_size / 2);

			cr.set_line_width (PLUS_LINE_WIDTH);
			cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
			cr.stroke_preserve ();

			return false;
		}
	}
	class DeepinWorkspaceAdder : Actor
	{
		public Meta.Screen screen { get; construct; }
		public const int FADE_DURATION = 200;
		public const AnimationMode FADE_MODE = AnimationMode.EASE_IN_OUT_CUBIC;
        public const int BACKGROUND_OPACITY = 60;

        DeepinWorkspaceAddButton btn;
        BlurredBackgroundActor background_actor;
        BackgroundSource background_source;
        DragDropAction window_drop_action;

        bool init = true;

		public DeepinWorkspaceAdder (Meta.Screen screen)
		{
            Object (screen: screen);
		}

		construct
		{
            background_source = BackgroundCache.get_default ().get_background_source (
				screen, BackgroundManager.BACKGROUND_SCHEMA, BackgroundManager.EXTRA_BACKGROUND_SCHEMA);
            background_actor = new BlurredBackgroundActor (screen, screen.get_primary_monitor ());
            update_background_actor ();
            background_actor.opacity = 0;
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

            btn = new DeepinWorkspaceAddButton ();
            notify["allocation"].connect (() => {
                float w = Math.floorf(width), h = Math.floorf(height);
                background_actor.set_size (w, h);
                set_rounded_radius (background_actor, 6);
                btn.set_size (w, h);
            });

			add_child (background_actor);
            add_child (btn);

			window_drop_action = new DragDropAction (
				DragDropActionType.DESTINATION, "deepin-multitaskingview-window");
			add_action (window_drop_action);
            window_drop_action.crossed.connect((hover) => {
                if (hover) {
                    update_background_actor ();
                }
                background_animate (hover, true);
            });
		}

        Cairo.Region? last_region = null;
        Cairo.Surface? last_blur_mask = null;
        void set_rounded_radius (Meta.BlurredBackgroundActor actor, int rd, bool forced = false)
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

        void update_background_actor ()
        {
            if (!init) {
                background_source.request_new_default_uri ();
            }
            init = false;
            //assign a non-exist workspace will give us default background
            var background = background_source.get_background (screen.get_n_workspaces ());
            background_actor.background = background.background;
        }

        void background_animate (bool show, bool do_scale)
        {
            if (just_reset && !show) {
                just_reset = false;
                return;
            }

            set_pivot_point (0.5f, 0.5f);
            just_reset = false;

            if (do_scale) {
                var scale = GLib.Value (typeof (float));

                if (show) {
                    scale.set_float (1.05f);
                } else {
                    scale.set_float (1.0f);
                }

                this.remove_all_transitions ();
                DeepinUtils.start_animation_group (this, "deepin-workspace-adder",
                        FADE_DURATION,
                        (timeline) => {
                            timeline.set_progress_mode (FADE_MODE);
                        }, "scale-x", scale, "scale-y", &scale);
            }

            var fading = new PropertyTransition ("opacity");
            fading.set_duration (FADE_DURATION);
            fading.set_from_value (show ? 0:BACKGROUND_OPACITY);
            fading.set_to_value (show ? BACKGROUND_OPACITY:0);
            fading.set_progress_mode (FADE_MODE);
            fading.remove_on_complete = true;

            background_actor.remove_all_transitions ();
            background_actor.add_transition ("fading", fading);
        }

        bool just_reset = false;
        public void reset ()
        {
            set_scale (1.0f, 1.0f);
            background_actor.remove_transition ("fading");
            background_actor.opacity = 0;
            just_reset = true;
        }

        public override bool leave_event (Clutter.CrossingEvent ev)
        {
            background_animate (false, false);
            return false;
        }

        public override bool enter_event (Clutter.CrossingEvent ev)
        {
            update_background_actor ();
            background_animate (true, false);
            return false;
        }
	}

	/**
	 * This class contains the DeepinWorkspaceThumbClone which placed in the top of multitaskingview
	 * and will take care of displaying actors for inserting windows between the groups once
	 * implemented.
	 */
	public class DeepinWorkspaceThumbContainer : Actor
	{
		/**
		 * The percent value between thumbnail workspace clone's width and monitor's width.
		 */
		public const float WORKSPACE_WIDTH_PERCENT = 0.12f;

		const int PLUS_FADE_IN_DURATION = 700;

		public signal void workspace_closing (Workspace workspace);
        
		/**
		 * The percent value between distance of thumbnail workspace clones and monitor's width.
		 */
		public const float SPACING_PERCENT = 0.02f;

		const int LAYOUT_DURATION = 300;

		public Screen screen { get; construct; }

		Actor plus_button;

		public DeepinWorkspaceThumbContainer (Screen screen)
		{
			Object (screen: screen);
		}

		construct
		{
			plus_button = new DeepinWorkspaceAdder (screen);
			plus_button.reactive = true;
			plus_button.set_pivot_point (0.5f, 0.5f);
			plus_button.button_press_event.connect (() => {
				append_new_workspace ();
				return false;
			});

			append_plus_button_if_need ();

			actor_removed.connect (on_actor_removed);

			screen.monitors_changed.connect (relayout);
		}

		~DeepinWorkspaceThumbContainer ()
		{
			screen.monitors_changed.disconnect (relayout);
		}

		public void append_new_workspace ()
		{
            DeepinUtils.append_new_workspace (screen);
		}

		public void open ()
		{
			append_plus_button_if_need ();
		}

		public void close ()
		{
			append_plus_button_if_need ();
		}

		public void add_workspace (DeepinWorkspaceThumbClone workspace_clone,
								   DeepinUtils.PlainCallback? cb = null)
		{
			var index = workspace_clone.workspace.index ();
			insert_child_at_index (workspace_clone, index);
            workspace_clone.x = plus_button.x;
            workspace_clone.y = plus_button.y;

			if (Prefs.get_num_workspaces () >= WindowManagerGala.MAX_WORKSPACE_NUM) {
                remove_child (plus_button);
            } else {
                plus_button_flash_in ();    
            }

			workspace_clone.start_fade_in_animation ();

            hide_workspace_close_button ();
            enable_workspace_drag_action ();
            if (cb != null) {
                cb ();
            }

			workspace_clone.closing.connect (on_workspace_closing);

			relayout ();
		}

        void plus_button_flash_in ()
        {
            ActorBox child_box = get_child_layout_box (screen, get_n_children (), false);
            plus_button.opacity = 0;
            plus_button.x = child_box.get_x () - child_box.get_width () / 2;
            plus_button.y = child_box.get_y ();

            (plus_button as DeepinWorkspaceAdder).reset ();

            plus_button.save_easing_state ();
            plus_button.set_easing_duration (LAYOUT_DURATION);
            plus_button.set_easing_mode (AnimationMode.LINEAR);
            plus_button.opacity = 255;
            plus_button.restore_easing_state ();
        }

		public void remove_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			workspace_clone.closing.disconnect (on_workspace_closing);

			remove_child (workspace_clone);

			append_plus_button_if_need ();

			relayout ();
		}

		void on_workspace_closing (DeepinWorkspaceThumbClone thumb_workspace)
		{
			workspace_closing (thumb_workspace.workspace);

			// workspace is closing, disable the dragging actions
			disable_workspace_drag_action ();
		}

		void on_actor_removed (Clutter.Actor actor)
		{
			// workspace removed and close animation finished, enable the dragging actions
			enable_workspace_drag_action ();
		}

		void enable_workspace_drag_action ()
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).enable_drag_action ();
				}
			}
		}

		void disable_workspace_drag_action ()
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).disable_drag_action ();
				}
			}
		}

		void hide_workspace_close_button ()
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).thumb_clone.show_close_button (false);
				}
			}
		}

		/**
		 * Make plus button visible if workspace number less than MAX_WORKSPACE_NUM.
		 */
		void append_plus_button_if_need ()
		{
			if (could_append_plus_button ()) {
				plus_button.opacity = 0;
				add_child (plus_button);
				DeepinUtils.start_fade_in_back_animation (plus_button, PLUS_FADE_IN_DURATION);

				relayout ();
			}
		}

		bool could_append_plus_button ()
		{
			if (Prefs.get_num_workspaces () < WindowManagerGala.MAX_WORKSPACE_NUM &&
				!contains (plus_button)) {
				return true;
			}
			return false;
		}

		public void relayout ()
		{
			var i = 0;
			foreach (var child in get_children ()) {
				place_child (child, i);
				i++;
			}
		}

		public void select_workspace (int index, bool animate)
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					var thumb_workspace = child as DeepinWorkspaceThumbClone;
					if (thumb_workspace.workspace.index () == index) {
						thumb_workspace.set_select (true, animate);
					} else {
						thumb_workspace.set_select (false, animate);
					}
				}
			}
		}

        public void start_reorder_workspace(Actor ws, Actor target)
        {
			var i = 0, j = 0, k = 0;
			foreach (var child in get_children ()) {
                if (child == ws) {
                    i = k;
                } else if (target == child) {
                    j = k;
                }
                k++;
			}
            //stderr.printf("switch %d => %d\n", i, j);
            set_child_at_index (ws, j);
            place_child (ws, j, false);

            int d = i < j ? 1 : -1;
            for (k = i; d > 0 ? k < j : k > j; k += d) {
                place_child (get_child_at_index (k), k);
            }
            //assert (ws == get_child_at_index(j));
            //assert (target == get_child_at_index(j-d));
        }

		public static void get_prefer_thumb_size (Screen screen, out float width, out float height)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			// calculate monitor width height ratio
			float monitor_whr = (float)monitor_geom.height / monitor_geom.width;

			width = monitor_geom.width * WORKSPACE_WIDTH_PERCENT;
			height = width * monitor_whr;
		}

		ActorBox get_child_layout_box (Screen screen, int index, bool is_thumb_clone = false)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			var box = ActorBox ();

			float child_x = 0, child_y = 0;
			float child_width = 0, child_height = 0;
			float child_spacing = monitor_geom.width * SPACING_PERCENT;

			get_prefer_thumb_size (screen, out child_width, out child_height);
			child_x = (child_width + child_spacing) * index;

			// place child center of monitor
			float container_width = child_width * get_n_children () + child_spacing * (get_n_children () - 1);
			float offset_x = ((float)monitor_geom.width - container_width) / 2;
			child_x += offset_x;

			box.set_size (child_width, child_height);
			box.set_origin (child_x, child_y);

			return box;
		}

		void place_child (Actor child, int index, bool animate = true)
		{
			ActorBox child_box = get_child_layout_box (screen, index,
													   child is DeepinWorkspaceThumbClone);
			child.width = child_box.get_width ();
			child.height = child_box.get_height ();

			if (animate) {
				// workspace is relayout, disable the drag action
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).disable_drag_action ();
				}

				var position = Point.alloc ();
				position.x = child_box.get_x ();
				position.y = child_box.get_y ();
				var position_value = GLib.Value (typeof (Point));
				position_value.set_boxed ((void*)position);
				DeepinUtils.start_animation_group (child, "thumb-workspace-slot", LAYOUT_DURATION,
                        (tl) => { tl.progress_mode = (AnimationMode.LINEAR); },
                        "position", &position_value);

				// enable the drag action after workspace relayout when plus button will not be
				// append later, which will queue relayout again
				if (child is DeepinWorkspaceThumbClone && !could_append_plus_button ()) {
					var thumb_clone = child as DeepinWorkspaceThumbClone;
					DeepinUtils.run_clutter_callback (thumb_clone, "thumb-workspace-slot", thumb_clone.enable_drag_action);
				}
			} else {
				child.x = child_box.get_x ();
				child.y = child_box.get_y ();
			}
		}
	}
}
