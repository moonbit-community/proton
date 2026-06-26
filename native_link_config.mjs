#!/usr/bin/env node

import { createNativeLinkConfig } from "./proton/native_link_config.mjs";

process.stdout.write(JSON.stringify(createNativeLinkConfig()));
