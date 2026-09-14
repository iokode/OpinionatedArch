// Answers with the image published most recently, with its checksum, and with
// the installation script.
//
// It reads the bucket rather than being told, so there is nothing to update
// when a new image goes up and nothing to go stale when an old one is deleted:
// the answer is derived from what is there at the moment it is asked.
//
// Images are named for the minute they were built, so the last one in order is
// the newest. The workflow that prunes them relies on the same thing, and both
// would have to change together if that name ever did.

const IMAGES = "https://iso.oparch.iokode.dev";

// The installation script as it is on master, which is where a merge puts it.
// Written here, in the repository the script is in, so that a change moving the
// script is the change that shows this has to follow it.
const INSTALL_SCRIPT =
  "https://raw.githubusercontent.com/iokode/OpinionatedArch/master/scripts/install.sh";

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;

    // Temporary, like the image's: where the script is kept can move, and a
    // permanent redirect is one that would go on being believed after it had.
    if (path === "/install.sh") {
      return Response.redirect(INSTALL_SCRIPT, 302);
    }

    const listed = await env.IMAGES.list();
    const images = listed.objects
      .map((object) => object.key)
      .filter((key) => key.endsWith(".iso"))
      .sort();

    const latest = images[images.length - 1];
    if (!latest) {
      return new Response("No image has been published yet.\n", { status: 404 });
    }

    // Two addresses and one lookup. The checksum is uploaded beside the image
    // under the image's own name with `.sha256` after it, so working out which
    // image is current is the whole of working out where either one is.
    const target = path.endsWith(".sha256") ? `${latest}.sha256` : latest;

    // Temporary, and deliberately so: this points somewhere else every day,
    // and a permanent redirect is one browsers would go on believing long
    // after the image it named had been deleted.
    return Response.redirect(`${IMAGES}/${target}`, 302);
  },
};
