import { fcm } from '../config/firebase.js';
import { FirebaseNotConfiguredError } from '../config/firebase-error.js';
import { prisma } from '../config/prisma.js';

// Firebase refuses a multicast to more devices than this.
const MAX_TOKENS_PER_SEND = 500;

async function send(tokens: string[], title: string, body: string, data?: Record<string, string>) {
  try {
    for (let i = 0; i < tokens.length; i += MAX_TOKENS_PER_SEND) {
      await fcm.sendEachForMulticast({
        tokens: tokens.slice(i, i + MAX_TOKENS_PER_SEND),
        notification: { title, body },
        data,
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } },
      });
    }
  } catch (err) {
    // Without a Firebase key (development only) the action goes on without the push.
    if (!(err instanceof FirebaseNotConfiguredError)) throw err;
    console.warn(`Push notification not sent, Firebase not configured: ${title}`);
  }
}

export async function pushToAll(title: string, body: string, data?: Record<string, string>) {
  const devices = await prisma.userDevice.findMany({
    where: { user: { status: 'active' } },
    select: { fcmToken: true },
  });
  await send(devices.map((d) => d.fcmToken), title, body, data);
}

// Waiting users: active users outside a group whose journey is still going on.
export async function pushToWaitingUsers(title: string, body: string, data?: Record<string, string>) {
  const devices = await prisma.userDevice.findMany({
    where: { user: { status: 'active', OR: [{ groupId: null }, { group: { endedAt: { lte: new Date() } } }] } },
    select: { fcmToken: true },
  });
  await send(devices.map((d) => d.fcmToken), title, body, data);
}

// Suspended requesters keep their request, but can't use the app until reactivated.
export async function pushToCycleRequesters(
  cycleId: string,
  title: string,
  body: string,
  data?: Record<string, string>,
) {
  const devices = await prisma.userDevice.findMany({
    where: { user: { status: 'active', participationRequests: { some: { cycleId } } } },
    select: { fcmToken: true },
  });
  await send(devices.map((d) => d.fcmToken), title, body, data);
}

export async function pushToGroup(groupId: string, title: string, body: string, data?: Record<string, string>) {
  const devices = await prisma.userDevice.findMany({
    where: { user: { status: 'active', groupId } },
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
        // Who is in the channel now: not those who left.
        sharingChannelSession: { some: { sharingChannelId: channelId, leftAt: null } },
      },
    },
    select: { fcmToken: true },
  });
  await send(devices.map((d) => d.fcmToken), title, body, data);
}
