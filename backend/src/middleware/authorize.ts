import { FastifyRequest, FastifyReply } from 'fastify';
import { Role } from '@prisma/client';

export const ROLE_RANK: Record<Role, number> = {
  user: 0,
  admin: 1,
  super_admin: 2,
};

// An admin acts on plain users, the Super Admin also on admins: nobody acts on
// themselves or on someone of equal or higher rank, hence never on the Super Admin.
export function outranks(actorRole: string, targetRole: Role) {
  return ROLE_RANK[actorRole as Role] > ROLE_RANK[targetRole];
}

export function authorize(minimumRole: Role) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    const userRole = request.user?.role as Role;
    if (!userRole || ROLE_RANK[userRole] < ROLE_RANK[minimumRole]) {
      return reply.status(403).send({ message: 'Permessi insufficienti' });
    }
  };
}
