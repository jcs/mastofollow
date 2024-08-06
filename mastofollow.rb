#!/usr/bin/env ruby
#
# Copyright (c) 2024 joshua stein <jcs@jcs.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

require "json"
require "nokogiri"
require "date"
require "erb"
require "sanitize"
require "webrick"

require "./sponge"

PER_PAGE = 100

ME = ARGV[0]
if !ME.to_s.match(/^https?:\/\/[^\/]+\/@.+/)
  puts "usage: #{$0} https://example.com/@you"
  exit 1
end

def h(str)
  CGI.escapeHTML(str.to_s)
end

def sanitize(html)
  Sanitize.fragment(html, Sanitize::Config::RELAXED)
end

s = Sponge.new
s.timeout = 15

followers = []
page = 1
while true do
  puts "fetching followers page #{page}..."
  js = s.fetch("#{ME}/followers.json?page=#{page}").json
  followers += js["orderedItems"]

  if js["next"]
    page += 1
  else
    break
  end
end

page = 1
while true do
  puts "fetching following page #{page}..."
  js = s.fetch("#{ME}/following.json?page=#{page}").json
  followers -= js["orderedItems"]

  if js["next"]
    page += 1
  else
    break
  end
end

statuses = []

followers.shuffle.each_with_index do |f,x|
  url = "#{f}.rss"
  print "fetching #{url} [#{x + 1}/#{followers.count}]"

  begin
    res = s.fetch(url, :get, nil, nil, { "Accept" => "application/rss+xml" })

    if res.ok?
      puts ""
    else
      puts " (failed #{res.status})"
      next
    end
  rescue Timeout::Error
    puts " (timed out)"
    next
  rescue => e
    puts " (#{e.message})"
    next
  end

  doc = Nokogiri::XML(res.body)

  user = {
    "url" => f,
  }

  if n = doc.xpath("//title")[0]
    user["name"] = n.text
  end

  if a = doc.xpath("//channel/image/url")[0]
    user["avatar"] = a.text
  end

  doc.xpath("//item").each do |i|
    u = i.xpath("link").text
    text = i.xpath("description").text

    if !i.xpath("pubDate").any?
      puts "  no pubDate for status #{u}"
      next
    end

    date = DateTime.parse(i.xpath("pubDate").text).to_time.localtime

    status = {
      "user" => user,
      "url" => i.xpath("link").text,
      "date" => DateTime.parse(i.xpath("pubDate").text).to_time.to_i,
      "text" => i.xpath("description").text,
      "attachments" => [],
    }

    begin
      i.xpath("media:content").each do |att|
        status["attachments"].push({
          "url" => att["url"],
          "medium" => att["medium"],
        })
      end
    rescue Nokogiri::XML::XPath::SyntaxError
    end

    statuses.push status
  end
end

File.write("statuses.json", statuses.to_json)

f = nil
page = 1
statuses.sort_by{|s| s["date"] }.reverse.each_with_index do |s,x|
  if f == nil
    f = File.open("statuses#{page == 1 ? "" : page}.html", "w+")
    f.puts <<-END
      <!doctype html>
      <html>
      <head>
        <meta http-equiv="content-type" content="text/html; charset=utf-8" />
        <meta name="referrer" content="never" />
        <link rel="stylesheet" type="text/css" href="style.css" />
      </head>
      <body>
    END
  end

  t = ERB.new <<-END
    <div class="status">
      <div class="date">
        <a href="<%= h(s["url"]) %>" target="_blank">
          <%= Time.at(s["date"]).strftime("%Y-%m-%d %H:%M:%S") %>
        </a>
      </div>
      <div class="avatar">
      <% if s["user"]["avatar"] %>
        <img src="<%= h(s["user"]["avatar"]) %>">
      <% end %>
      </div>
      <div class="title">
        <a href="<%= h(s["user"]["url"]) %>" target=\"_blank\">
          <%= h(s["user"]["name"]) %>
        </a>
      </div>
      <div class="user">
        <a href="<%= h(s["user"]["url"]) %>" target=\"_blank\">
          <%= h(s["user"]["url"]) %>
        </a>
      </div>
      <div class="body">
        <%= sanitize(s["text"]) %>
      </div>
      <% s["attachments"].each do |at| %>
        <div class="attachment">
          <% if at["medium"] == "video" %>
            <a href="<%= h(at["url"]) %>">Video: <%= h(at["url"]) %></a>
          <% else %>
            <img src="<%= h(at["url"]) %>">
          <% end %>
        </div>
      <% end %>
    </div>
  END
  f.write t.result(binding)

  if ((x + 1) % PER_PAGE == 0) || (x == statuses.count - 1)
    t = ERB.new <<-END
      <div class="pages">
        <% (statuses.count / PER_PAGE.to_f).ceil.times do |pp| %>
          <a href="statuses<%= pp == 0 ? "" : pp + 1 %>.html" class="page">
            <%= pp + 1 %>
          </a>
        <% end %>
      </div>
      </body>
      </html>
    END
    f.write t.result(binding)
    f.close

    f = nil
    page += 1
  end
end

puts "", "open the following URL to view statuses:", ""
puts "  http://127.0.0.1:8000/statuses.html", ""

server = WEBrick::HTTPServer.new(:Port => 8000, :DocumentRoot => Dir.pwd)
trap("INT") do
  server.shutdown
end
server.start
