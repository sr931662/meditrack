"""Medications, schedules and the escalation policy."""

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.api.deps import AuthContext, get_auth, get_household_access, page
from app.api.v1.schemas import (
    MedicationIn,
    MedicationOut,
    MedicationPatch,
    PolicyIn,
    ScheduleIn,
    ScheduleOut,
    SchedulePatch,
)
from app.core.db import get_db
from app.core.errors import AppError, NotFound
from app.models import Medication, Schedule, Senior
from app.services import audit, engine
from app.services.authz import HouseholdAccess

router = APIRouter(prefix="/households/{household_id}", tags=["care"])

MED_SORT = {"name": Medication.name, "created_at": Medication.created_at}


def _med(db: Session, access: HouseholdAccess, med_id: str) -> Medication:
    """Every lookup is scoped by household (and by senior for senior users): no cross-tenant IDOR."""
    q = db.query(Medication).filter_by(id=med_id, household_id=access.household_id)
    if access.role == "senior":
        q = q.filter(Medication.senior_id == access.senior_id)
    m = q.first()
    if m is None:
        raise NotFound("Medication not found")
    return m


@router.post("/medications", status_code=201, response_model=MedicationOut)
def create_medication(
    body: MedicationIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("medications.create")
    if db.query(Senior).filter_by(id=body.senior_id, household_id=access.household_id).first() is None:
        raise NotFound("Senior not found in this household")
    m = Medication(household_id=access.household_id, **body.model_dump())
    db.add(m)
    db.flush()
    audit.record(
        db,
        actor_id=auth.user.id,
        action="medication.created",
        target_type="medication",
        target_id=m.id,
        household_id=access.household_id,
        data={"name": m.name, "strength": m.strength},
    )
    return m


@router.get("/medications")
def list_medications(
    access: HouseholdAccess = Depends(get_household_access),
    db: Session = Depends(get_db),
    senior_id: str | None = None,
    include_inactive: bool = False,
    sort: str = Query("created_at", pattern="^(name|created_at)$"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    access.require("medications.read")
    q = db.query(Medication).filter_by(household_id=access.household_id)
    if access.role == "senior":
        senior_id = access.senior_id
    if senior_id:
        q = q.filter(Medication.senior_id == senior_id)
    if not include_inactive:
        q = q.filter(Medication.is_active.is_(True))
    total = q.with_entities(func.count()).scalar()
    rows = q.order_by(MED_SORT[sort]).limit(limit).offset(offset).all()
    return page([MedicationOut.model_validate(r).model_dump(mode="json") for r in rows], total, limit, offset)


@router.get("/medications/{med_id}", response_model=MedicationOut)
def get_medication(med_id: str, access: HouseholdAccess = Depends(get_household_access), db: Session = Depends(get_db)):
    access.require("medications.read")
    return _med(db, access, med_id)


@router.patch("/medications/{med_id}", response_model=MedicationOut)
def update_medication(
    med_id: str,
    body: MedicationPatch,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("medications.update")
    m = _med(db, access, med_id)
    changes = body.model_dump(exclude_unset=True)
    for k, v in changes.items():
        setattr(m, k, v)
    if m.start_date and m.end_date and m.end_date < m.start_date:
        raise AppError("end_date cannot be before start_date", code="validation_error", status_code=422)
    audit.record(
        db,
        actor_id=auth.user.id,
        action="medication.updated",
        target_type="medication",
        target_id=m.id,
        household_id=access.household_id,
        data={"fields": sorted(changes)},
    )
    return m


@router.delete("/medications/{med_id}", status_code=204)
def delete_medication(
    med_id: str,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    """Soft delete: dose history and audit trail must remain intact."""
    access.require("medications.delete")
    m = _med(db, access, med_id)
    m.is_active = False
    for s in db.query(Schedule).filter_by(medication_id=m.id):
        s.is_active = False
    audit.record(
        db,
        actor_id=auth.user.id,
        action="medication.deleted",
        target_type="medication",
        target_id=m.id,
        household_id=access.household_id,
    )
    return Response(status_code=204)


# ---- schedules ----------------------------------------------------------------------------------
def _sched(db: Session, access: HouseholdAccess, sid: str) -> Schedule:
    s = db.query(Schedule).filter_by(id=sid, household_id=access.household_id).first()
    if s is None or (access.role == "senior" and s.senior_id != access.senior_id):
        raise NotFound("Schedule not found")
    return s


@router.post("/schedules", status_code=201, response_model=ScheduleOut)
def create_schedule(
    body: ScheduleIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("schedules.manage")
    med = db.query(Medication).filter_by(id=body.medication_id, household_id=access.household_id).first()
    if med is None:
        raise NotFound("Medication not found")
    s = Schedule(household_id=access.household_id, senior_id=med.senior_id, **body.model_dump())
    db.add(s)
    db.flush()
    audit.record(
        db,
        actor_id=auth.user.id,
        action="schedule.created",
        target_type="schedule",
        target_id=s.id,
        household_id=access.household_id,
        data={"times": s.times},
    )
    return s


@router.get("/schedules")
def list_schedules(
    access: HouseholdAccess = Depends(get_household_access),
    db: Session = Depends(get_db),
    senior_id: str | None = None,
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    access.require("schedules.read")
    q = db.query(Schedule).filter_by(household_id=access.household_id, is_active=True)
    if access.role == "senior":
        senior_id = access.senior_id
    if senior_id:
        q = q.filter(Schedule.senior_id == senior_id)
    total = q.with_entities(func.count()).scalar()
    rows = q.order_by(Schedule.created_at).limit(limit).offset(offset).all()
    return page([ScheduleOut.model_validate(r).model_dump(mode="json") for r in rows], total, limit, offset)


@router.patch("/schedules/{schedule_id}", response_model=ScheduleOut)
def update_schedule(
    schedule_id: str,
    body: SchedulePatch,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("schedules.manage")
    s = _sched(db, access, schedule_id)
    changes = body.model_dump(exclude_unset=True, exclude_none=True)
    for k, v in changes.items():
        setattr(s, k, v)
    audit.record(
        db,
        actor_id=auth.user.id,
        action="schedule.updated",
        target_type="schedule",
        target_id=s.id,
        household_id=access.household_id,
        data={"fields": sorted(changes)},
    )
    return s


@router.delete("/schedules/{schedule_id}", status_code=204)
def delete_schedule(
    schedule_id: str,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("schedules.manage")
    s = _sched(db, access, schedule_id)
    s.is_active = False
    audit.record(
        db,
        actor_id=auth.user.id,
        action="schedule.deleted",
        target_type="schedule",
        target_id=s.id,
        household_id=access.household_id,
    )
    return Response(status_code=204)


# ---- escalation policy --------------------------------------------------------------------------
def _policy_out(p) -> dict:
    return {"t_verify_min": p.t_verify_min, "t_escalate_min": p.t_escalate_min, "contacts": p.contacts}


@router.get("/escalation-policy")
def get_policy(access: HouseholdAccess = Depends(get_household_access), db: Session = Depends(get_db)):
    access.require("escalation.read")
    return _policy_out(engine.get_policy(db, access.household_id))


@router.put("/escalation-policy")
def put_policy(
    body: PolicyIn,
    access: HouseholdAccess = Depends(get_household_access),
    auth: AuthContext = Depends(get_auth),
    db: Session = Depends(get_db),
):
    access.require("escalation.manage")
    p = engine.get_policy(db, access.household_id)
    p.t_verify_min, p.t_escalate_min = body.t_verify_min, body.t_escalate_min
    p.contacts = [c.model_dump() for c in body.contacts]
    db.flush()
    engine.reschedule_pending(db, access.household_id)
    audit.record(
        db,
        actor_id=auth.user.id,
        action="escalation_policy.updated",
        target_type="escalation_policy",
        target_id=p.id,
        household_id=access.household_id,
        data={"t_verify_min": p.t_verify_min, "t_escalate_min": p.t_escalate_min, "contacts": len(p.contacts)},
    )
    return _policy_out(p)
