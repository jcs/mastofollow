## mastofollow

### why

If you run your own Mastodon instance, you may also be frustrated by the
problem where you gain a new follower, you click through to view their profile,
but Mastodon just shows you this:

![notdisplayed](https://github.com/user-attachments/assets/a2e269b6-7b2a-4441-9de4-0b590e9f22f4)

I tell myself I'll do it later, and then I forget, and now I have a growing
list of followers that I haven't followed back because I can't quickly see
their list of recent posts to determine if they're a bot or a weirdo or someone
that only reposts political things.

### what

This is a hacky Ruby script that will:

1. Fetch your list of followers (paginating as necessary)
2. Fetch the RSS feed of each follower and gather their recent statuses
3. Sort all statuses in reverse chronological order
4. Dump out static HTML files of each page of statuses (100 at a time)
5. Spin up a WEBrick to provide a quick interface to view the static files

Once the HTML files are created, you can view them locally and see each status
with its image attachments and user avatars as a single feed.
From there, hopefully you can find some good content and follow some users
back.

### how

	$ git clone https://github.com/jcs/mastofollow
	$ cd mastofollow
	mastofollow$ bundle install
	[...]
	mastofollow$ bundle exec ruby mastofollow.rb https://example.com/@you
	fetching followers page 1...
	fetching followers page 2...
	[...]
	fetching https://.../users/steve.rss [1/...]
	fetching https://.../users/jakob.rss [2/...]

Where the `https://example.com/@you` argument is your canonical Mastodon URL.

After fetching everything, navigate to `http://127.0.0.1:8000/statuses.html` to
view the timeline.
It will look rather basic, like this:

![demo](https://github.com/user-attachments/assets/f71bd585-8bce-4a1e-8e84-204bc7ae4895)

### but

This program naively assumes that most followers will be using Mastodon
and Mastodon provides an RSS feed at `https://example.com/user.rss`.
It does not do proper WebFinger lookups or ActivityPub parsing.
If particular followers are not using Mastodon or their server does not provide
a `.rss` response, they will be skipped.
If their RSS feed does not provide `pubDate` dates for statuses, they will be
skipped.

The internal state of statuses is written out to `statuses.json` for further
inquiry, but everything is done in memory and each run starts over.
A SQLite backend or something could be added to reduce memory and browse
statuses in something other than static HTML, but this worked enough for me.
Don't run it too often.
