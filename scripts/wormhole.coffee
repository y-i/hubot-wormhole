# Description:
#   Script to inhale the message on any channels and
#   exhale it to a specific channel in another Workspace
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.
#
#   These are from the scripting documentation: https://github.com/github/hubot/blob/master/docs/scripting.md

module.exports = (robot) ->

  user = process.env.HUBOT_AMQP_USER
  pass = process.env.HUBOT_AMQP_PASSWORD
  url  = process.env.HUBOT_AMQP_URL
  isIn  = process.env.HUBOT_WORMHOLE_IN
  isOut = process.env.HUBOT_WORMHOLE_OUT

  if isIn == 'yes'
    localToGlobal = {}
    robot.hear /.*/i, (res) ->
      amqp = require('amqplib')
      amqp.connect("amqp://#{user}:#{pass}@#{url}")
        .then((conn) ->
          conn.createChannel().then((ch) ->
            ex = 'topic.wormhole'
            username = res.message.user.profile.display_name ||
                       res.message.user.profile.real_name ||
                       res.message.user.name
            icon = res.message.user.profile.image_192
            randomID = Math.floor(Math.random() * 10 * 1000 * 1000)
            messageID = res.message.id
            localToGlobal["#{messageID}"] = randomID
            payload = { id: randomID, message: { username: username, icon_url: icon, text: res.message.text, as_user: false } }

            robot.adapter.client.web.conversations.info(res.message.room)
              .then((response) ->
                key = "#{process.env.HUBOT_WORMHOLE_ROUTING_KEY}.#{response.channel.name}"
                ch.assertExchange(ex, 'topic', {durable: false})
                ch.publish(ex, key, Buffer.from(JSON.stringify(payload)))
              )
          )
        ).catch((reason) ->
          res.send("Error: #{reason}")
        )

  if isOut == 'yes'
    globalToLocal = {}
    amqp_cb = require('amqplib/callback_api')
    amqp_cb.connect("amqp://#{user}:#{pass}@#{url}", (err, conn) ->
      room = process.env.HUBOT_EXHALE_ROOM || "wormhole"
      send = (msg) -> robot.send {room: room}, msg
      if err
        send "Error: #{err}"
      else
        conn.createChannel((err, ch) ->
          if err
            send "createChannnel Error: #{err}"
          else
            ex = 'topic.wormhole'
            ch.assertExchange(ex, 'topic', {durable: false})
            ch.assertQueue('', {exclusive: true, durable: false}, (err, q) ->
              if err
                send "Error: #{err}"
              else
                keys = process.env.HUBOT_WORMHOLE_BINDING_KEYS
                for key in keys.split(',')
                  ch.bindQueue(q.queue, ex, key)

                ch.consume(q.queue, (msg) ->
                  room = msg.fields.routingKey.split('.').pop()
                  payload = JSON.parse(msg.content.toString())
                  randomID = payload.id
                  message = payload.message
                  ret = robot.send {room: room}, message
                  messageID = ret.ok && ret.ts
                  if messageID !== false
                    globalToLocal["#{randomID}"] = messageID
                  ch.ack(msg)
                )
            )
        )
    )
