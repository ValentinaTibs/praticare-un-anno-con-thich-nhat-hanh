import { FastifyRequest, FastifyReply } from 'fastify';
import { Role } from '@prisma/client';

const ROLE_RANK: Record<Role, number> = {
  user: 0,
  admin: 1,
  super_admin: 2,
};

export function authorize(minimumRole: Role) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const userRole = request.user?.role as Role;
    if (!userRole || ROLE_RANK[userRole] < ROLE_RANK[minimumRole]) {
      return reply.status(403).send({ message: 'Insufficient permissions' });
    }
  };
}
