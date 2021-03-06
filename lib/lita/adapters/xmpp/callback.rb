module Lita
  module Adapters
    class Xmpp < Adapter
      class Callback
        attr_reader :robot, :roster

        def initialize(robot, roster)
          @robot = robot
          @roster = roster
          @start_time = Time.now.utc
        end

        def private_message(client)
          client.add_message_callback do |m|
            next if m.type == :error || m.body.nil?
            user = user_by_jid(m.from)
            source = Source.new(user: user)
            message = Message.new(robot, m.body, source)
            message.command!
            Lita.logger.debug("Dispatching PM to Lita from #{user.id}.")
            robot.receive(message)
          end
        end

        def muc_message(muc)
          muc.on_message do |time, nick, text|
            if time.is_a?(Time) && time < @start_time
              Lita.logger.debug "#{time} < #{@start_time} Skipping #{nick}: #{text}"
              next
            else
              user = user_by_name(nick)
              source = Source.new(user: user, room: muc.jid.bare.to_s)
              message = Message.new(robot, text, source)
              Lita.logger.debug(
                "Dispatching message to Lita from #{user.id} in MUC #{muc.jid}."
              )
              robot.receive(message)
            end
          end
        end

        def roster_update
          roster.add_update_callback do |old_item, item|
            next unless item
            jid = item.attributes["jid"]
            Lita.logger.debug("Updating record for user with ID: #{jid}.")
            create_user(item.attributes)
          end
        end

        private

        def create_user(user_data)
          User.create(
            user_data["jid"],
            name: user_data["name"],
            mention_name: user_data["mention_name"]
          )
        end

        def user_by_jid(jid)
          Lita.logger.debug("Looking up user with JID: #{jid}.")
          create_user(roster[jid].attributes)
        end

        def user_by_name(name)
          Lita.logger.debug("Looking up user with name: #{name}.")
          items = roster.items.detect { |jid, item| item.iname == name }
          if items
            user_by_jid(items.first)
          elsif !Lita.config.adapters.ignore_unknown_users
            Lita.logger.warn <<-MSG.chomp
No user with the name #{name.inspect} was found in the roster. A temporary user has been created for
this message, but Lita will not be able to reply.
MSG
            User.new(nil, name: name)
          end
        end
      end
    end
  end
end
