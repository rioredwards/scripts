#!/usr/bin/env python3

import iterm2
import asyncio
import os
import random
import base64


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

        base64_image_path = base64.b64encode(random_image.encode()).decode()
        return base64_image_path

    async def get_profile_for_session(session_id):
        session = app.get_session_by_id(session_id)
        return await session.async_get_profile()

    @iterm2.RPC
    async def rand_bg(session_id):
        profile = await get_profile_for_session(session_id)
        rand_img = await getRandomImage()
        await profile.async_set_background_image_location(rand_img)

    await blend_more.async_register(connection)

    @iterm2.RPC
    async def blend_more(session_id):
        profile = await get_profile_for_session(session_id)
        await profile.async_set_blend(min(1, profile.blend + 0.1))

    await blend_more.async_register(connection)

    @iterm2.RPC
    async def blend_less(session_id):
        profile = await get_profile_for_session(session_id)
        await profile.async_set_blend(max(0, profile.blend - 0.1))

    await blend_less.async_register(connection)


iterm2.run_forever(main)
