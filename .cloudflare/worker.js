// Answers with the image published most recently.
//
// It reads the bucket rather than being told, so there is nothing to update
// when a new image goes up and nothing to go stale when an old one is deleted:
// the answer is derived from what is there at the moment it is asked.
//
// Images are named for the day they were built, so the last one in order is
// the newest. The workflow that prunes them relies on the same thing, and both
// would have to change together if that name ever did.

const IMAGES = "https://iso.oparch.iokode.dev";

export default {
  async fetch(request, env) {
    const listed = await env.IMAGES.list();
    const images = listed.objects
      .map((object) => object.key)
      .filter((key) => key.endsWith(".iso"))
      .sort();

    const latest = images[images.length - 1];
    if (!latest) {
      return new Response("No image has been published yet.\n", { status: 404 });
    }

    // Temporary, and deliberately so: this points somewhere else every month,
    // and a permanent redirect is one browsers would go on believing long
    // after the image it named had been deleted.
    return Response.redirect(`${IMAGES}/${latest}`, 302);
  },
};
