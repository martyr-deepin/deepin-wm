//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2013 Tom Beckmann
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

namespace Gala
{
	public enum DragDropActionType
	{
		SOURCE = 0,
		DESTINATION
	}

	public enum DragDropActionDirection
	{
		NONE = 0,
		LEFT = 1,
		RIGHT = 1 << 1,
		UP = 1 << 2,
		DOWN = 1 << 3,
		ALL = LEFT + RIGHT + UP + DOWN
	}

	public class DragDropAction : Clutter.Action
	{
		static Gee.HashMap<string,Gee.LinkedList<Actor>>? sources = null;

		/**
		 * A drag has been started. You have to connect to this signal and
		 * return an actor that is transformed during the drag operation.
		 *
		 * @param x The global x coordinate where the action was activated
		 * @param y The global y coordinate where the action was activated
		 * @return  A ClutterActor that serves as handle
		 */
		public signal Actor drag_begin (float x, float y);

		/**
		 * A drag has been canceled. You may want to consider cleaning up
		 * your handle.
		 */
		public signal void drag_canceled ();

		/**
		 * A drag action has successfully been finished.
		 *
		 * @param actor The actor on which the drag finished
		 */
		public signal void drag_end (Actor actor);

		/**
		 * A drag action is moving mouse
		 *
		 * @param delta_x is the dragging distance in x-axis
		 * @param delta_y is the dragging distance in y-axis
		 */
		public signal void drag_motion (float delta_x, float delta_y);

		/**
		 * The destination has been crossed
		 *
		 * @param hovered indicates whether the actor is now hovered or not
		 */
		public signal void crossed (bool hovered);

		/**
		 * Emitted on the source when a destination is crossed.
		 *
		 * @param destination The destination actor that has been crossed
		 * @param hovered     Whether the actor is now hovered or has just been left
		 */
		public signal void destination_crossed (Actor destination, bool hovered);

		/**
		 * The source has been clicked, but the movement was not larger than
		 * the drag threshold. Useful if the source is also activable.
		 *
		 * @param button The button which was pressed
		 */
		public signal void actor_clicked (uint32 button);

		/**
		 * The type of the action
		 */
		public DragDropActionType drag_type { get; construct; }

		/**
		 * The unique id given to this drag-drop-group
		 */
		public string drag_id { get; construct; }

		public Actor handle { get; private set; }
		/**
		 * Indicates whether a drag action is currently active
		 */
		public bool dragging { get; private set; default = false; }

		/**
		 * Allow checking the parents of reactive children if they are valid destinations
		 * if the child is none
		 */
		public bool allow_bubbling { get; set; default = true; }

		/**
		 * The axis type that allowed to follor mouse.
		 */
		public DragDropActionDirection allow_direction = DragDropActionDirection.ALL;

        /**
         * This is dirty: it means although Y direction is disabled, there is still
         * a small Y area where drag-moving is allowed.
         */
        public float allow_y_overflow = 0.0f;


		Actor? hovered = null;
		bool clicked = false;
		float orig_x;
		float orig_y;
        /** 
         * original offset of handle to cursor drag point
         */
        Point offset;
		float last_x;
		float last_y;

		/**
		 * Create a new DragDropAction
		 *
		 * @param type The type of this actor
		 * @param id   An ID that marks which sources can be dragged on
		 *             which destinations. It has to be the same for all actors that
		 *             should be compatible with each other.
		 */
		public DragDropAction (DragDropActionType type, string id)
		{
			Object (drag_type : type, drag_id : id);

			if (sources == null)
				sources = new Gee.HashMap<string,Gee.LinkedList<Actor>> ();
		}

		~DragDropAction ()
		{
			if (actor != null)
				release_actor (actor);
		}

		public override void set_actor (Actor? new_actor)
		{
			if (actor != null) {
				release_actor (actor);
			}

			if (new_actor != null) {
				connect_actor (new_actor);
			}

			base.set_actor (new_actor);
		}

		void release_actor (Actor actor)
		{
			if (drag_type == DragDropActionType.SOURCE) {
				actor.button_press_event.disconnect (source_clicked);

				var source_list = sources.@get (drag_id);
				source_list.remove (actor);
			}
		}

		void connect_actor (Actor actor)
		{
			if (drag_type == DragDropActionType.SOURCE) {
				actor.button_press_event.connect (source_clicked);

				var source_list = sources.@get (drag_id);
				if (source_list == null) {
					source_list = new Gee.LinkedList<Actor> ();
					sources.@set (drag_id, source_list);
				}

				source_list.add (actor);
			}
		}

		void emit_crossed (Actor destination, bool hovered)
		{
			get_drag_drop_action (destination).crossed (hovered);
			destination_crossed (destination, hovered);
		}

		bool source_clicked (ButtonEvent event)
		{
			if (event.button != 1) {
				actor_clicked (event.button);
				return false;
			}

			actor.get_stage ().captured_event.connect (follow_move);
			clicked = true;
			last_x = event.x;
			last_y = event.y;

			return true;
		}

        bool drag_allowed (Event event)
        {
            float x, y;
            event.get_coords (out x, out y);

            var drag_threshold = Clutter.Settings.get_default ().dnd_drag_threshold;

            if ((allow_direction & DragDropActionDirection.LEFT) == DragDropActionDirection.LEFT
                    && (last_x - x > drag_threshold)) {
                return true;
            }

            if ((allow_direction & DragDropActionDirection.RIGHT) == DragDropActionDirection.RIGHT
                    && (x - last_x > drag_threshold)) {
                return true;
            }

            if ((allow_direction & DragDropActionDirection.UP)  == DragDropActionDirection.UP
                    && (last_y - y > drag_threshold)) {
                return true;
            }

            if ((allow_direction & DragDropActionDirection.DOWN) == DragDropActionDirection.DOWN
                    && (y - last_y > drag_threshold)) {
                return true;
            }

            if (Math.fabsf(y - last_y) < allow_y_overflow) {
                return true;
            }

            return false;
        }

		bool follow_move (Event event)
		{
			// still determining if we actually want to start a drag action
			if (!dragging) {
				switch (event.get_type ()) {
					case EventType.MOTION:
						if (allow_direction == DragDropActionDirection.NONE) {
							return false;
						}

						float x, y;
						event.get_coords (out x, out y);

						if (drag_allowed (event)) {
							handle = drag_begin (x, y);
							if (handle == null) {
								// No handle has been returned by the started signal, aborting drag.
								actor.get_stage ().captured_event.disconnect (follow_move);
								return false;
							}

							// relayout target actor for that maybe reparent just now and could not
							// get the correct position
							handle.queue_relayout ();
                            orig_x = handle.x;
                            orig_y = handle.y;
                            offset = Point.zero ();
                            offset.x = x - orig_x;
                            offset.y = y - orig_y;

							handle.reactive = false;

							clicked = false;
							dragging = true;

							var source_list = sources.@get (drag_id);
							if (source_list != null) {
								foreach (var actor in source_list) {
									actor.reactive = false;
								}
							}
						}
						return true;
					case EventType.BUTTON_RELEASE:
						float x, y, ex, ey;
						event.get_coords (out ex, out ey);
						actor.get_transformed_position (out x, out y);

						// release has happened within bounds of actor
						if (x < ex && x + actor.width > ex && y < ey && y + actor.height > ey) {
							actor_clicked (event.get_button ());
						}

						actor.get_stage ().captured_event.disconnect (follow_move);
						clicked = false;
						dragging = false;
						return true;
					default:
						return true;
				}
			}

			switch (event.get_type ()) {
				case EventType.KEY_PRESS:
					if (event.get_key_code () == Key.Escape) {
						cancel ();
					}
					return true;

				case EventType.MOTION:
					float x, y;
					event.get_coords (out x, out y);

					// limit dragging direction
					if ((allow_direction & DragDropActionDirection.LEFT) ==
						DragDropActionDirection.LEFT) {
						if ((x - offset.x) <= orig_x) {
                            handle.x = x - offset.x;
						}
					}
					if ((allow_direction & DragDropActionDirection.RIGHT) ==
						DragDropActionDirection.RIGHT) {
						if ((x - offset.x) >= orig_x) {
                            handle.x = x - offset.x;
						}
					}
					if ((allow_direction & DragDropActionDirection.UP) ==
						DragDropActionDirection.UP) {
						if ((y - offset.y) <= orig_y) {
                            handle.y = y - offset.y;
						}
					}
					if ((allow_direction & DragDropActionDirection.DOWN) ==
						DragDropActionDirection.DOWN) {
						if ((y - offset.y) >= orig_y) {
                            handle.y = y - offset.y;
						}
					}

                    if (allow_y_overflow > 0.0f) {
                        var d = y - offset.y - orig_y;
                        if (d < allow_y_overflow) 
                            handle.y = y - offset.y;
                    }

                    if (handle.x != orig_x || handle.y != orig_y)
                        drag_motion (handle.x - orig_x, handle.y - orig_y);

					var stage = actor.get_stage ();
					var actor = stage.get_actor_at_pos (PickMode.REACTIVE, (int) x, (int) y);
					DragDropAction action = null;
					// if we're allowed to bubble and this actor is not a destination, check its parents
					if (actor != null && actor != stage && 
                            (action = get_drag_drop_action (actor)) == null && allow_bubbling) {
						while ((actor = actor.get_parent ()) != stage) {
							if ((action = get_drag_drop_action (actor)) != null)
								break;
						}
					}

					// didn't change, no need to do anything
					if (actor == hovered)
						return true;

					if (action == null) {
						// apparently we left ours if we had one before
						if (hovered != null) {
							emit_crossed (hovered, false);
							hovered = null;
						}

						return true;
					}

					// signal the previous one that we left it
					if (hovered != null) {
						emit_crossed (hovered, false);
					}

					// tell the new one that it is hovered
					hovered = actor;
					emit_crossed (hovered, true);

					return true;
				case EventType.BUTTON_RELEASE:
					if (hovered != null) {
						finish ();
					} else {
						cancel ();
					}
					return true;
				case EventType.ENTER:
				case EventType.LEAVE:
					return true;
			}

			return false;
		}

		/**
		 * Looks for a DragDropAction instance if this actor has one or NULL.
		 * It also checks if it is a DESTINATION and if the id matches
		 *
		 * @return the DragDropAction instance on this actor or NULL
		 */
		DragDropAction? get_drag_drop_action (Actor actor)
		{
			DragDropAction? drop_action = null;

			foreach (var action in actor.get_actions ()) {
				drop_action = action as DragDropAction;
				if (drop_action == null
					|| drop_action.drag_type != DragDropActionType.DESTINATION
					|| drop_action.drag_id != drag_id)
					continue;

				return drop_action;
			}

			return null;
		}

		/**
		 * Abort the drag
		 */
		public void cancel ()
		{
			cleanup ();

			drag_canceled ();
		}

		/**
		 * Allows you to abort all drags currently running for a given drag-id
		 */
		public static void cancel_all_by_id (string id)
		{
			var actors = sources.@get (id);
			if (actors == null)
				return;

			foreach (var actor in actors) {
				foreach (var action in actor.get_actions ()) {
					var drag_action = action as DragDropAction;
					if (drag_action != null && drag_action.dragging) {
						drag_action.cancel ();
						break;
					}
				}
			}
		}

		void finish ()
		{
			// make sure they reset the style or whatever they changed when hovered
			emit_crossed (hovered, false);

			cleanup ();

			drag_end (hovered);
		}

		void cleanup ()
		{
			var source_list = sources.@get (drag_id);
			if (source_list != null) {
				foreach (var actor in source_list) {
					actor.reactive = true;
				}
			}

			if (dragging)
				actor.get_stage ().captured_event.disconnect (follow_move);

			dragging = false;
		}
	}
}
