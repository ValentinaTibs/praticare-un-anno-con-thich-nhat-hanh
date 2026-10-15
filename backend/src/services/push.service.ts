import { fcm } from '../config/firebase.js';
import { prisma } from '../config/prisma.js';

async function send(tokens: string[], title: string, body: string, data?: Record<string, string>) {
  if (!tokens.length) return;
  await fcm.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default' } } },
  });
}

export async function pushToAll(title: string, body: string, data?: Record<string, string>) {
  const devices = await prisma.userDevice.findMany({
    where: { user: { status: 'active' } },
    select: { fcmToken: true },
  });
  await send(devices.map((d) => d.fcmToken), title, body, data);
}

export async function pushToUser(userId: string, title: string, body: string, data?: Record<string, string>) {
  const devices = await prisma.userDevice.findMany({
    where: { userId },
    select: { fcmToken: true },
  });
  await send(devices.map((d) => d.fcmToken), title, body, data);
}

export async function pushToChannelMembers(channelId: string, title: string, body: string, data?: Record<string, string>) {
  const devices = await prisma.userDevice.findMany({
    where: {
      user: {
        status: 'active',
        sharingChannelSession: { some: { sharingChannelId: channelId } },
      },
    },
    select: { fcmToken: true },
  });
  await send(devices.map((d) => d.fcmToken), title, body, data);
}
