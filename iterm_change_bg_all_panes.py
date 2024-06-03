#!/usr/bin/env python3

import iterm2
import os
import random


async def main(connection):
    app = await iterm2.async_get_app(connection)

    async def getRandomImage():
        image_folder = "/Users/rioedwards/Pictures/iterm_bg_photos"

        image_files = [
            f
            for f in os.listdir(image_folder)
            if os.path.isfile(os.path.join(image_folder, f))
        ]

        random_image = os.path.join(image_folder, random.choice(image_files))

        return random_image

    async def get_profile_for_session(session_id):
        session = app.get_session_by_id(session_id)
        return await session.async_get_profile()

    @iterm2.RPC
    async def rand_bg(session_id):
        profile = await get_profile_for_session(session_id)
        rand_img = await getRandomImage()
        print(rand_bg)
        await profile.async_set_background_image_location(rand_img)

    await rand_bg.async_register(connection)
    print("Registered rand_bg")


iterm2.run_forever(main)
